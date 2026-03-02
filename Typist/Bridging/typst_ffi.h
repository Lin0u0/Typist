#pragma once
#include <stdint.h>
#include <stdbool.h>

/// Options for typst_compile. All pointer fields may be NULL.
typedef struct {
    /// Extra font file paths (e.g. system CJK fonts from CoreText).
    const char * const *font_paths;
    size_t              font_path_count;
    /// Directory for caching downloaded @preview packages.
    const char         *cache_dir;
} TypstOptions;

/// Result returned by typst_compile. Free with typst_free_result.
typedef struct {
    uint8_t *pdf_data;       ///< Non-null on success.
    size_t   pdf_len;
    char    *error_message;  ///< Null-terminated string on failure.
    bool     success;
} TypstResult;

/// Compile a null-terminated UTF-8 Typst source string to PDF.
/// options may be NULL to use bundled fonts only and skip package support.
TypstResult typst_compile(const char *source, const TypstOptions *options);

/// Free a TypstResult returned by typst_compile.
void typst_free_result(TypstResult result);
