#pragma once
#include <stdint.h>
#include <stddef.h>

typedef struct SnipperArchive SnipperArchive;
SnipperArchive *sn_archive_open(const char *path);
// Returns 1 for an entry, 0 at EOF, -1 on error. Kind: 1 regular, 2 directory, 0 other.
int sn_archive_next(SnipperArchive *reader, const char **path, int64_t *size, int *kind);
int64_t sn_archive_read(SnipperArchive *reader, void *buffer, size_t capacity);
void sn_archive_close(SnipperArchive *reader);
