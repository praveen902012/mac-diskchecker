# Disk Checker — first version

Build a local macOS app using SwiftUI. No account or network service. User-requested cleanup: confirmed moves to Trash for items larger than 1 GB inside Desktop, Downloads, and Documents.

1. Scan a user-selected folder in the background; support cancellation and report unreadable folders.
2. Rank immediate children by allocated disk size, with recursive drill-down, breadcrumbs, search, and Finder reveal.
3. Show volume capacity separately from scanned totals and visualize the largest children.
4. Explain common storage categories without asserting files are safe to delete.
5. Test scanner accounting, hidden files, symlinks, hard links, and cancellation; package a launchable app.

Accounting: use allocated file sizes where available, count hard-linked files once, do not follow symlinks or cross onto other mounted volumes. APFS shared blocks, snapshots, and inaccessible data mean a folder scan is not equivalent to the system's used-storage total. Show these limits in the interface.

Later: scan comparisons, duplicate detection, guided cleanup, and distribution signing.

Implemented cleanup: per-row Delete action, path/size confirmation, recoverable Trash moves, folder scope validation, scan refresh, and eligibility tests.

Implemented Desktop screenshot cleanup: metadata/name detection, review list and total size, confirmed bulk Trash action independent of the 1 GB limit, changed-file checks, partial-failure reporting, and storage refresh.
