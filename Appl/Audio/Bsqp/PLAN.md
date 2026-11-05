# BSQP folder playback plan

Status: implemented. Host checks and EC/NC builds pass.
The UI and audible behavior still need manual acceptance checks in GEOS.

## Scope

Show the MP3 and WAV files from one opened folder in a scrolling list below
the LCD. Read only that folder. Do not read subfolders.

Keep the existing audio decoder, LCD, Play/Pause, Stop, level meter, and
MP3 quality option. Add folder selection, track activation, continued
playback, and shuffle. Do not add playlist files, a media database, tag
editing, album art, or folder monitoring.

## User behavior

- Change Open to Open Folder. Use the native directory selector. Its
  confirmation button opens the directory currently shown in the selector,
  including a drive root or a folder with no subfolders. Double-clicking a
  directory navigates into it; it does not start playback.
- Cancel leaves the current folder and playback unchanged. Confirming a
  readable folder stops the old track, loads its list, selects its first
  entry, and waits for Play. If the folder cannot be read or stored, report
  the error and retain the old list. An empty folder is a valid result.
- Show the opened folder path above the list. Sort rows by filename without
  regard to case. Metadata changes the displayed text, not the row order.
- For MP3, show artist and title when available. With only a title, show the
  title. Without a usable title, show the filename, including its extension.
  For WAV, show the filename. Keep the original filename for file access.
- A single click or cursor-key movement selects a row without interrupting
  playback. Double-click or Enter starts that row. Play starts the selection
  while idle and retains its current Pause/Resume function during playback.
- Distinguish the playing row from the selection with a short text marker.
  Automatic playback selects and scrolls to the newly started row. Provide
  keyboard access to the list, folder selector, and options.
- With an empty list, clear the track display and disable Play. Show a short
  message such as No MP3 or WAV files in this folder.
- Opening the same folder again refreshes the list. Files added or removed
  externally are otherwise detected on the next folder open or play attempt.

## Playback options

- Continue Playing defaults to off. When on, a track that ends normally
  starts the next track. Stop at the end of the folder.
- Shuffle defaults to off. It changes the order used by Continue Playing;
  it does not start playback by itself. Explicitly playing a row starts that
  row first, then chooses randomly from the unplayed rows. Each row plays at
  most once in a run. A one-file folder plays once.
- Keep the existing Repeat Mode bit and rename its label to Repeat Current
  Track. It repeats the current track and takes priority over Continue
  Playing and Shuffle. This preserves existing saved settings. Folder
  repeat is outside this first version.
- Stop cancels advancement and repetition. Pause does not change the order.
  After Stop or the end of a run, Play starts a new run from the selection.
  Explicitly activating another row also starts a new run.
- Turning Continue Playing off lets the current track finish, then stops.
  Turning it on permits advancement at the next normal end. Turning Shuffle
  on starts a new shuffled remainder with the current row already visited.
  Turning it off resumes filename order after the current row.
- Save the new bits through the existing QuickPlayer options setting and
  Save Options command. Preserve all existing bit values.

## File manager launches

Use one process-side path for both initial launch and a new IACP request to
an already running instance. Read the supplied disk handle, directory, and
filename from the AppLaunchBlock. Load that directory, find the supplied
file by its filename, select it, scroll it into view, and start it.

The explicitly requested file always plays first, including with Shuffle
enabled. The selected playback options control what happens after it ends.
Keep the application open after playback. Remove the old quick-play exit
behavior. Starting the app without a file leaves an empty list until a
folder is opened; no startup scan is needed.

Copy launch data before releasing its memory block. Forward IACP launch
data from the application/UI thread to the process thread in owned memory.
Do not change shared path or list state from the UI thread. If requests
arrive while a stop or scan is pending, the newest request replaces the
pending request. Cancelled scan results must not replace the newer folder.

The product template already associates WAV and MP3 with BSQP. No file
manager change is planned. Check both GeoManager and ISDesk launch paths.
An inaccessible folder or missing requested file produces an error; it
must not play a different file instead.

## Directory list and memory

Use GenDynamicListClass for the scrolling list. Supply row text from stored
records in its query handler. Do not create a GenItem object for every file
or perform file reads from a moniker query.

Use FileEnum in bounded batches with the existing case-insensitive WAV/MP3
extension rule. Exclude directories. Save and restore the thread directory
around enumeration. Do not probe or decode every audio file during a scan.
An extension match makes a row eligible; actual playback validates it.

Store folder identity once as a disk handle and directory path. Store each
filename, bounded display text, tag state, and shuffle-visited flag in a
native HugeArray in one temporary VM file. This avoids a single 64 KB list
block and one memory handle per track. Use filename-ordered insertion for
the first version; do not add a separate sorting subsystem. Build a new
list separately and replace the old list only after enumeration succeeds.

Keep enumeration and tag buffers at or below 8 KB. Release locks before UI
calls or other operations that can move memory. Keep stack buffers small.
Close all temporary files and free list storage on replacement and exit.
Check native list identifier/count limits and allocation failures. Report
an oversized directory instead of silently showing part of it. Batched
FileEnum supports 32768 matching files because its skip counter uses a
signed test. The callback also counts matches to detect overflow of the
native word-sized count. Larger folders require callback-based streaming.

Show filenames as soon as enumeration finishes. Read MP3 tags in short
queued batches and replace the affected row text. Prioritize the requested
launch file so playback does not wait for all metadata. Cancel pending tag
work when the folder changes or the app closes. Use one metadata file
handle at a time. Bound work per batch so the UI can process other events.

## MP3 tag reader

The current decoder skips ID3 data but exposes no title or artist API.
Keep this display-only reader inside BSQP; do not change the decoder ABI.

- Read title and artist from ID3v2.2, v2.3, and v2.4 text frames. Fall back
  to ID3v1/v1.1 fields when the newer fields are absent or unusable.
- Support Latin-1, UTF-8, and the ID3 UTF-16 forms. Convert to the GEOS
  character set with platform conversion routines where available. Replace
  unrepresentable characters safely. Trim padding and control characters.
- Stream frame headers and seek over unrelated payloads. Do not allocate
  the declared tag size or read embedded pictures. Limit each output field
  to 80 characters and combine the fields in a bounded row buffer.
- Validate versions, flags, synchsafe sizes, frame sizes, file boundaries,
  integer arithmetic, and short reads before using data or seeking.
  Handle extended headers and unsynchronization for supported forms.
  Skip compressed or encrypted frames. Put a fixed work/read budget on each
  file: 8 KB of ID3v2 reads, at most 256 frames, and one 128-byte ID3v1
  fallback read. Tags that exceed the budget fall back to ID3v1 or filename.
  The source has an ATTENTION comment and tests for these limits.
- Bad or unsupported tags affect the label only. They do not remove a row,
  show repeated dialogs, write to the file, or prevent audio playback.

## Playback coordination

Keep list state and advancement on the process thread. The playback worker
plays one track, closes its reader and file, then queues completion. Move
Repeat Current Track handling out of the worker loop so all restart and
advance decisions use one process-side path.

Give each playback request a serial number. Include it in completion and
start-failure messages. Ignore obsolete completions. Track a pending
replacement separately from the playing track and selected row. A user
stop, folder change, or shutdown cancels automatic advancement before it
requests a worker stop. Start a replacement only after the old worker has
released playback. A stop timeout must not start a second worker.

Advance or repeat only after a successful natural end for the current
request. Abort, stop, failed open, decoder error, and resource error stop
the run and retain the existing single-error-dialog behavior. Do not skip
bad files automatically in this version. This prevents repeated errors or
an endless retry loop. A stale completion must not change current controls
or show an error for an obsolete request.

For shuffle, keep a visited flag per row and choose a random rank among
unvisited rows. Resolve that rank by scanning the stored records. This
needs no shuffled copy of the list. Mark the explicitly started row as
visited. Stop when no unvisited row remains.

Use the actual buffer capacity for all path construction and reject
overflow. The current code passes 256 for the 250-byte fullPath buffer and
appends strings without bounds checks. Replace the affected launch/open
path construction as part of this work.

## Change scope and order

1. Add folder storage, bounded enumeration, the native list, folder label,
   and directory selector. Remove the old selector-only audio filter and
   its class export if they are no longer used. Verify generated list
   queries and empty-folder behavior before metadata work.
2. Add playback request identity, pending replacement, and process-side
   completion handling. Route cold launch, IACP launch, and row activation
   through it. Remove quick-play exit handling. Keep one worker at a time.
3. Add Continue Playing and Shuffle. Retain Repeat Current Track and option
   compatibility. Test advancement independently from audio decoding.
4. Add bounded ID3 label extraction and queued metadata updates.

The folder coordinator is in Main/folder.goc and the bounded ID3 reader
is in Main/tags.goc. Existing Main and UI files provide the worker, LCD,
options, and launch entry points. Update bsqp.gp only for actual resource/export
changes. No new library dependency is planned. Preserve source line endings.

## Verification

Extend Tests/check.pl with small host checks that execute the production
logic using the existing C89 harness. Add generated binary tag fixtures in
temporary storage rather than committing music files.

- Enumeration: mixed-case extensions, unrelated files, directories, roots,
  empty folders, multiple batches, duplicate tag titles, and list limits.
- Tags: each supported version/encoding, partial fields, ID3v1 fallback,
  oversized artwork, extended headers, unsynchronization, malformed lengths,
  truncated input, output truncation, and the parser work ceiling.
- Playback: sequential end, shuffled uniqueness, zero/one/many rows,
  repeat precedence, pause, stop near EOF, failed play, deleted files,
  rapid track/folder changes, shutdown, and stale completions.
- Launch: cold start and existing-instance requests, requested-file lookup,
  case differences, missing files, and maximum-length paths.
- Ownership: failed scans preserve the old list; cancellation and errors
  close file handles and release all temporary storage.

Run the host checks and build EC and NC through aihelp.py build
Appl/Audio/Bsqp. Check git diff --ignore-space-at-eol. Ensure ~/swat.rc has
send bsqp and ends with c after any build. Do not start PC/GEOS for tests.
List layout, keyboard behavior, selector navigation, file manager launches,
and audible transitions remain manual acceptance checks for the user.
