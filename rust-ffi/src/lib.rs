use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::io::Read;
use std::os::raw::c_char;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use typst::diag::{FileError, FileResult, PackageError, SourceDiagnostic};
use typst::foundations::{Bytes, Datetime};
use typst::layout::PagedDocument;
use typst::syntax::package::PackageSpec;
use typst::syntax::{FileId, Source, Span, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};
use typst_pdf::{PdfOptions, pdf};

const EXTRA_FONT_CACHE_LIMIT: usize = 16;

static BUNDLED_FONT_FACES: OnceLock<Arc<Vec<Font>>> = OnceLock::new();
static EXTRA_FONT_FACES_CACHE: OnceLock<Mutex<HashMap<String, Arc<Vec<Font>>>>> = OnceLock::new();

#[cfg(debug_assertions)]
macro_rules! debug_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*);
    };
}

#[cfg(not(debug_assertions))]
macro_rules! debug_log {
    ($($arg:tt)*) => {};
}

// ---------------------------------------------------------------------------
// C FFI — options struct
// ---------------------------------------------------------------------------

/// Compile options passed from Swift.
///
/// All pointer fields may be null to opt out of that feature.
#[repr(C)]
pub struct TypstOptions {
    /// Array of extra font file paths (e.g. system CJK fonts).
    pub font_paths: *const *const c_char,
    pub font_path_count: usize,
    /// Directory used to cache downloaded @preview packages.
    pub cache_dir: *const c_char,
    /// Root directory for resolving local file references (e.g. #image("images/photo.jpg")).
    pub root_dir: *const c_char,
}

// ---------------------------------------------------------------------------
// In-memory Typst World
// ---------------------------------------------------------------------------

struct SimpleWorld {
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<Font>,
    main_id: FileId,
    source: Source,
    /// Root directory for the package cache (if provided).
    pkg_cache_root: Option<PathBuf>,
    /// Root directory for resolving local file references (images, imports).
    root_dir: Option<PathBuf>,
    /// Maps "ns/name/ver" → Ok(extracted dir) | Err(message).
    pkg_dirs: Mutex<HashMap<String, Result<PathBuf, String>>>,
    /// Per-request source cache (avoids re-reading the same file).
    source_cache: Mutex<HashMap<FileId, Source>>,
    /// Per-request binary file cache.
    file_cache: Mutex<HashMap<FileId, Bytes>>,
}

impl SimpleWorld {
    /// Construct a world.
    ///
    /// # Safety
    /// `options` must be null or point to a valid `TypstOptions`.
    unsafe fn new(source_text: &str, options: *const TypstOptions) -> Self {
        let bundled_faces = bundled_font_faces();
        let mut fonts: Vec<Font> = Vec::with_capacity(bundled_faces.len());
        let mut book = FontBook::new();

        // --- Bundled fonts (Latin, Math, Mono), parsed once then cloned ---
        for font in bundled_faces.iter().cloned() {
            book.push(font.info().clone());
            fonts.push(font);
        }

        let bundled_count = fonts.len();
        debug_log!("[typst-ffi] bundled fonts: {}", bundled_count);

        let mut pkg_cache_root: Option<PathBuf> = None;
        let mut root_dir: Option<PathBuf> = None;
        let mut font_paths: Vec<String> = Vec::new();

        if !options.is_null() {
            let opts = &*options;

            debug_log!("[typst-ffi] font_path_count from Swift: {}", opts.font_path_count);

            // Gather extra font paths from Swift.
            for i in 0..opts.font_path_count {
                let ptr = *opts.font_paths.add(i);
                if ptr.is_null() {
                    continue;
                }
                let path = match CStr::from_ptr(ptr).to_str() {
                    Ok(s) => s.to_string(),
                    Err(_) => continue,
                };
                font_paths.push(path);
            }

            // --- Package cache directory ---
            if !opts.cache_dir.is_null() {
                if let Ok(s) = CStr::from_ptr(opts.cache_dir).to_str() {
                    pkg_cache_root = Some(PathBuf::from(s));
                }
            }

            // --- Root directory for local file resolution ---
            if !opts.root_dir.is_null() {
                if let Ok(s) = CStr::from_ptr(opts.root_dir).to_str() {
                    if !s.is_empty() {
                        root_dir = Some(PathBuf::from(s));
                        debug_log!("[typst-ffi] root_dir: {}", s);
                    }
                }
            }
        }

        // --- Extra font paths (system CJK fonts from Swift/CoreText) ---
        if !font_paths.is_empty() {
            let extra_faces = extra_font_faces(&font_paths);
            for font in extra_faces.iter().cloned() {
                book.push(font.info().clone());
                fonts.push(font);
            }
            debug_log!(
                "[typst-ffi] loaded {} extra font faces (cache key paths: {})",
                extra_faces.len(),
                font_paths.len()
            );
        }

        let main_id = FileId::new(None, VirtualPath::new("main.typ"));
        let source = Source::new(main_id, source_text.to_string());

        Self {
            library: LazyHash::new(Library::default()),
            book: LazyHash::new(book),
            fonts,
            main_id,
            source,
            pkg_cache_root,
            root_dir,
            pkg_dirs: Mutex::new(HashMap::new()),
            source_cache: Mutex::new(HashMap::new()),
            file_cache: Mutex::new(HashMap::new()),
        }
    }

    /// Return (and download if needed) the local directory for a package.
    fn package_dir(&self, spec: &PackageSpec) -> FileResult<PathBuf> {
        let key = format!("{}/{}/{}", spec.namespace, spec.name, spec.version);

        {
            let guard = self.pkg_dirs.lock().unwrap();
            if let Some(result) = guard.get(&key) {
                return result
                    .clone()
                    .map_err(|_| FileError::Package(PackageError::NotFound(spec.clone())));
            }
        }

        let cache_root = self
            .pkg_cache_root
            .as_ref()
            .ok_or(FileError::Package(PackageError::NotFound(spec.clone())))?;

        let pkg_dir = cache_root
            .join(spec.namespace.as_str())
            .join(spec.name.as_str())
            .join(spec.version.to_string());

        let result = if pkg_dir.exists() {
            Ok(pkg_dir.clone())
        } else {
            let url = format!(
                "https://packages.typst.org/{}/{}-{}.tar.gz",
                spec.namespace, spec.name, spec.version
            );
            download_and_extract(&url, &pkg_dir).map(|_| pkg_dir.clone())
        };

        self.pkg_dirs.lock().unwrap().insert(key, result.clone());
        result.map_err(|_| FileError::Package(PackageError::NotFound(spec.clone())))
    }

    fn format_span_location(&self, span: Span) -> Option<String> {
        let id = span.id()?;
        let source = self.source(id).ok()?;
        let range = source.range(span).or_else(|| span.range())?;
        let (line, column) = source.lines().byte_to_line_column(range.start)?;
        Some(format!(
            "{}:{}:{}",
            self.display_file_label(id),
            line + 1,
            column + 1
        ))
    }

    fn display_file_label(&self, id: FileId) -> String {
        if let Some(package) = id.package() {
            format!("{package}{}", id.vpath().as_rooted_path().display())
        } else {
            id.vpath().as_rootless_path().display().to_string()
        }
    }
}

fn bundled_font_faces() -> Arc<Vec<Font>> {
    BUNDLED_FONT_FACES
        .get_or_init(|| {
            let mut faces = Vec::new();
            for data in typst_assets::fonts() {
                for font in Font::iter(Bytes::new(data)) {
                    faces.push(font);
                }
            }
            Arc::new(faces)
        })
        .clone()
}

fn extra_font_faces(paths: &[String]) -> Arc<Vec<Font>> {
    let key = paths.join("\u{1F}");
    let cache = EXTRA_FONT_FACES_CACHE.get_or_init(|| Mutex::new(HashMap::new()));

    {
        let guard = cache.lock().unwrap();
        if let Some(cached) = guard.get(&key) {
            return cached.clone();
        }
    }

    let mut faces: Vec<Font> = Vec::new();
    let mut failed = 0usize;
    for path in paths {
        match std::fs::read(path) {
            Ok(data) => {
                for font in Font::iter(Bytes::new(data)) {
                    faces.push(font);
                }
            }
            Err(e) => {
                debug_log!("[typst-ffi] FAILED to read font: {} — {}", path, e);
                failed += 1;
            }
        }
    }
    debug_log!(
        "[typst-ffi] extra font cache miss: {} faces, {} files failed",
        faces.len(),
        failed
    );

    let faces = Arc::new(faces);
    let mut guard = cache.lock().unwrap();
    if guard.len() >= EXTRA_FONT_CACHE_LIMIT {
        guard.clear();
    }
    guard.insert(key, faces.clone());
    faces
}

/// Download a `.tar.gz` from `url` and extract it into `dest`.
fn download_and_extract(url: &str, dest: &Path) -> Result<PathBuf, String> {
    let response = ureq::get(url)
        .call()
        .map_err(|e| format!("download failed: {e}"))?;

    let mut buf = Vec::new();
    response
        .into_reader()
        .read_to_end(&mut buf)
        .map_err(|e| format!("read failed: {e}"))?;

    let staging_dir = make_staging_directory(dest)?;
    if let Err(error) = extract_tar_gz_bytes(&buf, &staging_dir) {
        let _ = std::fs::remove_dir_all(&staging_dir);
        return Err(error);
    }

    std::fs::rename(&staging_dir, dest).map_err(|e| format!("rename failed: {e}"))?;

    Ok(dest.to_owned())
}

fn make_staging_directory(dest: &Path) -> Result<PathBuf, String> {
    let parent = dest
        .parent()
        .ok_or_else(|| format!("invalid destination path: {}", dest.display()))?;
    std::fs::create_dir_all(parent).map_err(|e| format!("mkdir failed: {e}"))?;

    let suffix = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|e| format!("clock error: {e}"))?
        .as_nanos();
    let file_name = dest
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("package");
    let staging_dir = parent.join(format!(".{file_name}.extracting-{suffix}"));

    if staging_dir.exists() {
        std::fs::remove_dir_all(&staging_dir).map_err(|e| format!("cleanup failed: {e}"))?;
    }
    std::fs::create_dir_all(&staging_dir).map_err(|e| format!("mkdir failed: {e}"))?;
    Ok(staging_dir)
}

fn extract_tar_gz_bytes(bytes: &[u8], dest: &Path) -> Result<(), String> {
    let gz = flate2::read::GzDecoder::new(std::io::Cursor::new(bytes));
    let mut archive = tar::Archive::new(gz);

    let entries = archive
        .entries()
        .map_err(|e| format!("archive entries failed: {e}"))?;

    for entry in entries {
        let mut entry = entry.map_err(|e| format!("archive entry failed: {e}"))?;
        let entry_type = entry.header().entry_type();

        if entry_type.is_symlink() || entry_type.is_hard_link() {
            return Err("archive contains unsupported link entries".to_string());
        }

        let relative_path = sanitized_archive_path(
            &entry
                .path()
                .map_err(|e| format!("archive path failed: {e}"))?,
        )?;

        if relative_path.as_os_str().is_empty() {
            continue;
        }

        let target_path = dest.join(&relative_path);
        if entry_type.is_dir() {
            std::fs::create_dir_all(&target_path).map_err(|e| format!("mkdir failed: {e}"))?;
            continue;
        }

        if !entry_type.is_file() {
            return Err(format!("archive contains unsupported entry type: {entry_type:?}"));
        }

        if let Some(parent) = target_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("mkdir failed: {e}"))?;
        }
        entry
            .unpack(&target_path)
            .map_err(|e| format!("extract failed: {e}"))?;
    }

    Ok(())
}

fn sanitized_archive_path(path: &Path) -> Result<PathBuf, String> {
    let mut sanitized = PathBuf::new();

    for component in path.components() {
        match component {
            Component::CurDir => continue,
            Component::Normal(part) => sanitized.push(part),
            Component::Prefix(_) | Component::RootDir | Component::ParentDir => {
                return Err(format!("unsafe archive path: {}", path.display()));
            }
        }
    }

    Ok(sanitized)
}

impl World for SimpleWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    fn main(&self) -> FileId {
        self.main_id
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        if id == self.main_id {
            return Ok(self.source.clone());
        }

        // Check cache first
        if let Some(src) = self.source_cache.lock().unwrap().get(&id).cloned() {
            return Ok(src);
        }

        // Resolve the file path
        let path = if let Some(spec) = id.package() {
            let pkg_dir = self.package_dir(spec)?;
            pkg_dir.join(id.vpath().as_rootless_path())
        } else {
            // Local file — resolve against root_dir
            let root = self.root_dir.as_ref().ok_or_else(|| {
                FileError::NotFound(id.vpath().as_rootless_path().to_owned())
            })?;
            root.join(id.vpath().as_rootless_path())
        };

        let text = std::fs::read_to_string(&path)
            .map_err(|_| FileError::NotFound(path.clone()))?;
        let src = Source::new(id, text);
        self.source_cache.lock().unwrap().insert(id, src.clone());
        Ok(src)
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        // Check cache first
        if let Some(b) = self.file_cache.lock().unwrap().get(&id).cloned() {
            return Ok(b);
        }

        // Resolve the file path
        let path = if let Some(spec) = id.package() {
            let pkg_dir = self.package_dir(spec)?;
            pkg_dir.join(id.vpath().as_rootless_path())
        } else {
            // Local file (e.g. images) — resolve against root_dir
            let root = self.root_dir.as_ref().ok_or_else(|| {
                FileError::NotFound(id.vpath().as_rootless_path().to_owned())
            })?;
            root.join(id.vpath().as_rootless_path())
        };

        let data = std::fs::read(&path)
            .map_err(|_| FileError::NotFound(path.clone()))?;
        let bytes = Bytes::new(data);
        self.file_cache.lock().unwrap().insert(id, bytes.clone());
        Ok(bytes)
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index).cloned()
    }

    fn today(&self, offset: Option<i64>) -> Option<Datetime> {
        use std::time::{SystemTime, UNIX_EPOCH};
        let secs = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        let total = secs + offset.unwrap_or(0) * 3600;
        let (y, m, d) = unix_days_to_ymd((total / 86400) as i32);
        Datetime::from_ymd(y, m, d)
    }
}

/// https://howardhinnant.github.io/date_algorithms.html
fn unix_days_to_ymd(mut days: i32) -> (i32, u8, u8) {
    days += 719468;
    let era = days.div_euclid(146097);
    let doe = days.rem_euclid(146097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i32 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m as u8, d as u8)
}

// ---------------------------------------------------------------------------
// C FFI — result type and compile/free functions
// ---------------------------------------------------------------------------

/// Result returned across the FFI boundary. Free with `typst_free_result`.
#[repr(C)]
pub struct TypstResult {
    pub pdf_data: *mut u8,
    pub pdf_len: usize,
    pub error_message: *mut c_char,
    pub success: bool,
}

/// Compile Typst source to PDF.
///
/// # Safety
/// `source` must be a valid null-terminated UTF-8 C string.
/// `options` may be null (disables CJK fonts and package downloads).
/// Free the result with `typst_free_result`.
#[no_mangle]
pub unsafe extern "C" fn typst_compile(
    source: *const c_char,
    options: *const TypstOptions,
) -> TypstResult {
    if source.is_null() {
        return error_result("null source pointer");
    }
    let source_str = match CStr::from_ptr(source).to_str() {
        Ok(s) => s,
        Err(_) => return error_result("source is not valid UTF-8"),
    };

    let world = SimpleWorld::new(source_str, options);

    match typst::compile::<PagedDocument>(&world).output {
        Ok(document) => match pdf(&document, &PdfOptions::default()) {
            Ok(bytes) => {
                let len = bytes.len();
                let mut boxed = bytes.into_boxed_slice();
                let ptr = boxed.as_mut_ptr();
                std::mem::forget(boxed);
                TypstResult {
                    pdf_data: ptr,
                    pdf_len: len,
                    error_message: std::ptr::null_mut(),
                    success: true,
                }
            }
            Err(e) => error_result(&format_diagnostics(&world, &e)),
        },
        Err(e) => error_result(&format_diagnostics(&world, &e)),
    }
}

/// Free a `TypstResult` returned by `typst_compile`.
///
/// # Safety
/// Must have been returned by `typst_compile` and not yet freed.
#[no_mangle]
pub unsafe extern "C" fn typst_free_result(result: TypstResult) {
    if !result.pdf_data.is_null() {
        drop(Box::from_raw(std::slice::from_raw_parts_mut(
            result.pdf_data,
            result.pdf_len,
        )));
    }
    if !result.error_message.is_null() {
        drop(CString::from_raw(result.error_message));
    }
}

/// Get the embedded typst-ios crate version.
///
/// Returns a pointer to a static null-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn typst_version() -> *const c_char {
    static VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "\0");
    VERSION.as_ptr() as *const c_char
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn error_result(msg: &str) -> TypstResult {
    let c = CString::new(msg).unwrap_or_else(|_| CString::new("error").unwrap());
    TypstResult {
        pdf_data: std::ptr::null_mut(),
        pdf_len: 0,
        error_message: c.into_raw(),
        success: false,
    }
}

fn format_diagnostics(world: &SimpleWorld, diags: &[SourceDiagnostic]) -> String {
    diags
        .iter()
        .map(|diag| format_diagnostic(world, diag))
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn format_diagnostic(world: &SimpleWorld, diag: &SourceDiagnostic) -> String {
    let mut lines = vec![diag.message.to_string()];

    if let Some(location) = world.format_span_location(diag.span) {
        lines.push(format!("({location})"));
    }

    lines.extend(diag.hints.iter().map(|hint| format!("Hint: {hint}")));

    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use flate2::Compression;
    use flate2::write::GzEncoder;
    use tar::{Builder, EntryType, Header};

    #[test]
    fn extract_tar_gz_bytes_extracts_regular_files() {
        let archive = build_tar_gz(vec![
            TarEntry::file("main.typ", b"hello"),
            TarEntry::file("nested/image.png", &[1, 2, 3]),
        ]);
        let dest = make_temp_dir();

        extract_tar_gz_bytes(&archive, &dest).unwrap();

        assert_eq!(std::fs::read_to_string(dest.join("main.typ")).unwrap(), "hello");
        assert_eq!(std::fs::read(dest.join("nested/image.png")).unwrap(), vec![1, 2, 3]);

        let _ = std::fs::remove_dir_all(dest);
    }

    #[test]
    fn extract_tar_gz_bytes_rejects_parent_traversal() {
        let error = sanitized_archive_path(Path::new("../escape.typ")).unwrap_err();

        assert!(error.contains("unsafe archive path"));
    }

    #[test]
    fn extract_tar_gz_bytes_rejects_symlink_entries() {
        let archive = build_tar_gz(vec![TarEntry::symlink("assets/link", "../outside")]);
        let dest = make_temp_dir();

        let error = extract_tar_gz_bytes(&archive, &dest).unwrap_err();

        assert!(error.contains("unsupported link entries"));
        let _ = std::fs::remove_dir_all(dest);
    }

    #[test]
    fn format_diagnostics_includes_source_location() {
        let world = unsafe { SimpleWorld::new("= broken", std::ptr::null()) };
        let span = Span::from_range(world.main(), 0..1);
        let rendered =
            format_diagnostics(&world, &[SourceDiagnostic::error(span, "unexpected token")]);

        assert!(rendered.contains("unexpected token"));
        assert!(rendered.contains("(main.typ:1:1)"));
    }

    #[derive(Clone)]
    struct TarEntry<'a> {
        path: &'a str,
        entry_type: EntryType,
        data: &'a [u8],
        link_name: Option<&'a str>,
    }

    impl<'a> TarEntry<'a> {
        fn file(path: &'a str, data: &'a [u8]) -> Self {
            Self {
                path,
                entry_type: EntryType::Regular,
                data,
                link_name: None,
            }
        }
        fn symlink(path: &'a str, target: &'a str) -> Self {
            Self {
                path,
                entry_type: EntryType::Symlink,
                data: &[],
                link_name: Some(target),
            }
        }
    }

    fn build_tar_gz(entries: Vec<TarEntry<'_>>) -> Vec<u8> {
        let encoder = GzEncoder::new(Vec::new(), Compression::default());
        let mut builder = Builder::new(encoder);

        for entry in entries {
            let mut header = Header::new_gnu();
            header.set_entry_type(entry.entry_type);
            header.set_mode(if entry.entry_type.is_dir() { 0o755 } else { 0o644 });
            header.set_size(entry.data.len() as u64);
            if let Some(link_name) = entry.link_name {
                header.set_link_name(link_name).unwrap();
            }
            header.set_cksum();
            builder
                .append_data(&mut header, entry.path, entry.data)
                .unwrap();
        }

        builder.into_inner().unwrap().finish().unwrap()
    }

    fn make_temp_dir() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "typst-ios-tests-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }
}
