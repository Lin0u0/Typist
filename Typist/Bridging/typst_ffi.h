#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/// Options for typst_compile. All pointer fields may be NULL.
typedef struct {
    /// Extra font file paths (e.g. system CJK fonts from CoreText).
    const char * const *font_paths;
    size_t              font_path_count;
    /// Directory for caching downloaded @preview packages.
    const char         *cache_dir;
    /// Root directory for resolving local file references (e.g. images).
    const char         *root_dir;
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

/// A single source-map entry mapping a PDF position to a source location.
typedef struct {
    uint32_t page;            ///< 0-based page index.
    float    y_pt;            ///< Y in PDF points from page top.
    float    x_pt;            ///< X in PDF points from page left.
    uint32_t source_offset;   ///< Byte offset in source.
    uint16_t source_length;   ///< Byte length of mapped range.
    uint32_t line;            ///< 1-based line number.
    uint16_t column;          ///< 1-based column number.
} SourceMapEntry;

/// Extended result with PDF data and source map.
/// Free with typst_free_result_with_map.
typedef struct {
    uint8_t        *pdf_data;
    size_t          pdf_len;
    char           *error_message;
    bool            success;
    SourceMapEntry *source_map;
    size_t          source_map_len;
} TypstResultWithMap;

/// Compile Typst source to PDF and extract a source map.
/// options may be NULL. Free with typst_free_result_with_map.
TypstResultWithMap typst_compile_with_source_map(const char *source,
                                                  const TypstOptions *options);

/// Free a TypstResultWithMap.
void typst_free_result_with_map(TypstResultWithMap result);

/// Returns typst-ios crate version (static UTF-8 string).
const char *typst_version(void);
