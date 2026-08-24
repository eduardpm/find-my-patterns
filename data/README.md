# data/

Your diary lives here as `diary.db`.

It sits outside the backend directory on purpose: the diary outlives any particular implementation
of the server, and should never be inside a directory anyone might delete while replacing the app.

Use `npm run backup -- /secure/path/diary-YYYY-MM-DD.db` from `backend/`. It uses SQLite's online
backup mechanism, so the snapshot is consistent even if the server is running. Backups contain
plain-text private writing; keep them on encrypted, access-controlled, preferably off-device media.

For recovery, stop the backend before replacing this file and keep the displaced copy until the
restored diary has been checked in Today, Calendar, and Insights.
