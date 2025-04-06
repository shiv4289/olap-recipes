# [brin.c](https://github.com/postgres/postgres/blob/master/src/backend/access/brin/brin.c) File Methods Documentation

## Overview
This file implements the BRIN (Block Range INdexes) index access method for PostgreSQL. BRIN indexes store summaries of values in consecutive blocks of a table, which can significantly reduce the amount of data scanned for certain types of queries.

## Methods

### 1. `brinhandler(PG_FUNCTION_ARGS)`
- **Purpose**: Returns an `IndexAmRoutine` structure with function pointers to various operations that can be performed on BRIN indexes.
- **Details**: This includes operations like building, inserting, vacuuming, and scanning the index.

### 2. `initialize_brin_insertstate(Relation idxRel, IndexInfo *indexInfo)`
- **Purpose**: Initializes a `BrinInsertState` structure to maintain state across multiple tuple inserts within the same command.
- **Details**: Sets up the BRIN descriptor and revmap access.

### 3. `brininsert(Relation idxRel, Datum *values, bool *nulls, ItemPointer heaptid, Relation heapRel, IndexUniqueCheck checkUnique, bool indexUnchanged, IndexInfo *indexInfo)`
- **Purpose**: Inserts a tuple into a BRIN index, updating the index summary values as necessary.
- **Details**: Checks if the range is summarized and updates the index tuple if needed.

### 4. `brininsertcleanup(Relation index, IndexInfo *indexInfo)`
- **Purpose**: Cleans up the `BrinInsertState` after all tuple inserts are done.
- **Details**: Releases resources and terminates the revmap.

### 5. `brinbeginscan(Relation r, int nkeys, int norderbys)`
- **Purpose**: Initializes state for a BRIN index scan.
- **Details**: Reads the metapage to determine the pages-per-range number and initializes the revmap access.

### 6. `bringetbitmap(IndexScanDesc scan, TIDBitmap *tbm)`
- **Purpose**: Executes the index scan and returns matching pages in the output bitmap.
- **Details**: Reads index tuples, compares them to scan keys, and adds matching pages to the bitmap.

### 7. `brinrescan(IndexScanDesc scan, ScanKey scankey, int nscankeys, ScanKey orderbys, int norderbys)`
- **Purpose**: Re-initializes state for a BRIN index scan.
- **Details**: Preprocesses the scan keys and updates the scan key data.

### 8. `brinendscan(IndexScanDesc scan)`
- **Purpose**: Closes down a BRIN index scan.
- **Details**: Terminates the revmap and releases resources.

### 9. `brinbuildCallback(Relation index, ItemPointer tid, Datum *values, bool *isnull, bool tupleIsAlive, void *brstate)`
- **Purpose**: Callback function for building a BRIN index.
- **Details**: Updates the running state with the values of the current tuple and summarizes the range if necessary.

### 10. `brinbuildCallbackParallel(Relation index, ItemPointer tid, Datum *values, bool *isnull, bool tupleIsAlive, void *brstate)`
- **Purpose**: Similar to `brinbuildCallback`, but used for parallel index builds.
- **Details**: Writes BRIN tuples into a shared tuplesort and leaves the insertion to the leader.

### 11. `brinbuild(Relation heap, Relation index, IndexInfo *indexInfo)`
- **Purpose**: Builds a new BRIN index.
- **Details**: Scans the table, constructs index tuples, and inserts them into the index.

### 12. `brinbuildempty(Relation index)`
- **Purpose**: Initializes an empty BRIN index.
- **Details**: Creates the metapage and logs it.

### 13. `brinbulkdelete(IndexVacuumInfo *info, IndexBulkDeleteResult *stats, IndexBulkDeleteCallback callback, void *callback_state)`
- **Purpose**: Handles bulk deletion for BRIN indexes.
- **Details**: Updates index statistics and marks ranges for summarization if necessary.

### 14. `brinvacuumcleanup(IndexVacuumInfo *info, IndexBulkDeleteResult *stats)`
- **Purpose**: Performs vacuum cleanup on a BRIN index.
- **Details**: Summarizes unsummarized ranges and updates index statistics.

### 15. `brinoptions(Datum reloptions, bool validate)`
- **Purpose**: Processes BRIN index options.
- **Details**: Parses and validates index options like `pages_per_range` and `autosummarize`.

### 16. `brin_summarize_new_values(PG_FUNCTION_ARGS)`
- **Purpose**: SQL-callable function to summarize new values in a BRIN index.
- **Details**: Calls `brin_summarize_range` for all unsummarized ranges.

### 17. `brin_summarize_range(PG_FUNCTION_ARGS)`
- **Purpose**: SQL-callable function to summarize a specific range in a BRIN index.
- **Details**: Summarizes the specified range or all unsummarized ranges if `BRIN_ALL_BLOCKRANGES` is passed.

### 18. `brin_desummarize_range(PG_FUNCTION_ARGS)`
- **Purpose**: SQL-callable function to mark a range as no longer summarized.
- **Details**: Updates the revmap to remove the summary for the specified range.

### 19. `brin_build_desc(Relation rel)`
- **Purpose**: Builds a `BrinDesc` structure, which describes the BRIN index.
- **Details**: Initializes the BRIN descriptor with opclass information.

### 20. `brin_free_desc(BrinDesc *bdesc)`
- **Purpose**: Frees a `BrinDesc` structure.
- **Details**: Deletes the memory context associated with the descriptor.

### 21. `brinGetStats(Relation index, BrinStatsData *stats)`
- **Purpose**: Fetches statistical data for a BRIN index.
- **Details**: Reads the metapage and retrieves statistics like `pagesPerRange` and `revmapNumPages`.

### 22. `initialize_brin_buildstate(Relation idxRel, BrinRevmap *revmap, BlockNumber pagesPerRange, BlockNumber tablePages)`
- **Purpose**: Initializes a `BrinBuildState` structure for building a BRIN index.
- **Details**: Sets up the initial state, including the revmap access and memory context.

### 23. `terminate_brin_buildstate(BrinBuildState *state)`
- **Purpose**: Releases resources associated with a `BrinBuildState`.
- **Details**: Frees memory and updates the free space map.

### 24. `summarize_range(IndexInfo *indexInfo, BrinBuildState *state, Relation heapRel, BlockNumber heapBlk, BlockNumber heapNumBlks)`
- **Purpose**: Summarizes the heap page range corresponding to the given block number.
- **Details**: Inserts a placeholder tuple, scans the heap, and updates the index tuple.

### 25. `brinsummarize(Relation index, Relation heapRel, BlockNumber pageRange, bool include_partial, double *numSummarized, double *numExisting)`
- **Purpose**: Summarizes unsummarized ranges in a BRIN index.
- **Details**: Scans the revmap and summarizes ranges, updating index statistics.

### 26. `form_and_insert_tuple(BrinBuildState *state)`
- **Purpose**: Forms an index tuple from the build state and inserts it into the index.
- **Details**: Converts the deformed tuple into an on-disk format and updates the revmap.

### 27. `form_and_spill_tuple(BrinBuildState *state)`
- **Purpose**: Forms an index tuple from the build state and writes it to a shared tuplesort.
- **Details**: Used for parallel index builds to defer insertion to the leader.

### 28. `union_tuples(BrinDesc *bdesc, BrinMemTuple *a, BrinTuple *b)`
- **Purpose**: Merges two deformed tuples.
- **Details**: Updates the first tuple to include summary values from both tuples.

### 29. `brin_vacuum_scan(Relation idxrel, BufferAccessStrategy strategy)`
- **Purpose**: Scans the index during vacuum to clean up any possible mess in each page.
- **Details**: Cleans up index pages and updates the free space map.

### 30. `add_values_to_range(Relation idxRel, BrinDesc *bdesc, BrinMemTuple *dtup, const Datum *values, const bool *nulls)`
- **Purpose**: Adds values to the range represented by the deformed tuple.
- **Details**: Updates the summary values and null flags in the deformed tuple.

### 31. `check_null_keys(BrinValues *bval, ScanKey *nullkeys, int nnullkeys)`
- **Purpose**: Checks if the null keys match the summary values in the range.
- **Details**: Evaluates IS NULL and IS NOT NULL scan keys against the summary values.

### 32. `_brin_begin_parallel(BrinBuildState *buildstate, Relation heap, Relation index, bool isconcurrent, int request)`
- **Purpose**: Begins a parallel index build, launching worker processes.
- **Details**: Sets up shared state and initializes the parallel context.

### 33. `_brin_end_parallel(BrinLeader *brinleader, BrinBuildState *state)`
- **Purpose**: Ends a parallel index build, shutting down worker processes and destroying the parallel context.
- **Details**: Accumulates WAL and buffer usage and releases resources.

### 34. `_brin_parallel_heapscan(BrinBuildState *state)`
- **Purpose**: Waits for the end of the heap scan in the leader process during a parallel index build.
- **Details**: Copies scan results from shared state to the leader's state.

### 35. `_brin_parallel_merge(BrinBuildState *state)`
- **Purpose**: Merges the per-worker results into the complete index after parallel index build.
- **Details**: Combines summaries for the same page range and fills in empty summaries.

### 36. `_brin_parallel_estimate_shared(Relation heap, Snapshot snapshot)`
- **Purpose**: Estimates the size of shared memory required for a parallel BRIN index build.
- **Details**: Calculates the memory needed for shared state and parallel scan descriptor.

### 37. `_brin_leader_participate_as_worker(BrinBuildState *buildstate, Relation heap, Relation index)`
- **Purpose**: Makes the leader participate as a worker in the parallel index build.
- **Details**: Joins the parallel scan and builds the index for the leader's portion.

### 38. `_brin_parallel_scan_and_build(BrinBuildState *state, BrinShared *brinshared, Sharedsort *sharedsort, Relation heap, Relation index, int sortmem, bool progress)`
- **Purpose**: Performs a worker's portion of a parallel sort, generating a tuplesort for the worker portion of the table.
- **Details**: Joins the parallel scan and builds the index tuplesort for the worker.

### 39. `_brin_parallel_build_main(dsm_segment *seg, shm_toc *toc)`
- **Purpose**: Main function for a parallel worker in a BRIN index build.
- **Details**: Opens relations, joins the parallel scan, and builds the index tuplesort.

### 40. `brin_build_empty_tuple(BrinBuildState *state, BlockNumber blkno)`
- **Purpose**: Initializes a BRIN tuple representing an empty range.
- **Details**: Builds the empty tuple once and reuses it for subsequent calls.

### 41. `brin_fill_empty_ranges(BrinBuildState *state, BlockNumber prevRange, BlockNumber nextRange)`
- **Purpose**: Adds BRIN index tuples representing empty page ranges.
- **Details**: Inserts empty tuples for ranges without any tuples in the index.
