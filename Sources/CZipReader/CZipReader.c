#include "CZipReader.h"
#include <stdlib.h>
#include <sys/types.h>

// macOS ships libarchive but does not expose its headers in the SDK.
// These declarations cover only the stable public C ABI used by this wrapper.
struct archive;
struct archive_entry;
extern struct archive *archive_read_new(void);
extern int archive_read_support_format_zip(struct archive *);
extern int archive_read_open_filename(struct archive *, const char *, size_t);
extern int archive_read_next_header(struct archive *, struct archive_entry **);
extern ssize_t archive_read_data(struct archive *, void *, size_t);
extern int archive_read_free(struct archive *);
extern const char *archive_entry_pathname(struct archive_entry *);
extern int64_t archive_entry_size(struct archive_entry *);
extern mode_t archive_entry_filetype(struct archive_entry *);
extern const char *archive_entry_hardlink(struct archive_entry *);
extern const char *archive_entry_symlink(struct archive_entry *);

struct SnipperArchive { struct archive *archive; };
SnipperArchive *sn_archive_open(const char *path) {
    SnipperArchive *reader = calloc(1, sizeof(*reader));
    if (!reader) return NULL;
    reader->archive = archive_read_new();
    if (!reader->archive || archive_read_support_format_zip(reader->archive) != 0 ||
        archive_read_open_filename(reader->archive, path, 65536) != 0) {
        sn_archive_close(reader);
        return NULL;
    }
    return reader;
}
int sn_archive_next(SnipperArchive *reader, const char **path, int64_t *size, int *kind) {
    struct archive_entry *entry = NULL;
    int status = archive_read_next_header(reader->archive, &entry);
    if (status == 1) return 0; // ARCHIVE_EOF
    if (status != 0) return -1; // Reject warnings as well as fatal errors.
    *path = archive_entry_pathname(entry);
    *size = archive_entry_size(entry);
    unsigned int type = archive_entry_filetype(entry);
    *kind = type == 0100000 ? 1 : type == 0040000 ? 2 : 0;
    if (archive_entry_hardlink(entry) || archive_entry_symlink(entry)) *kind = 0;
    return 1;
}
int64_t sn_archive_read(SnipperArchive *reader, void *buffer, size_t capacity) {
    return archive_read_data(reader->archive, buffer, capacity);
}
void sn_archive_close(SnipperArchive *reader) {
    if (!reader) return;
    if (reader->archive) archive_read_free(reader->archive);
    free(reader);
}
