package utv;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.FileNotFoundException;
import java.io.OutputStream;

/** Serves the file being shared straight from memory (no disk cache) with its real name. */
public final class Share extends ContentProvider {
    static volatile byte[] data = new byte[0];
    static volatile String name = "file.txt", mime = "text/plain";
    static volatile java.io.File file; // seekable backing file (real file, or temp copy deleted on exit)

    static Uri set(byte[] d, String n, String m, java.io.File f) {
        data = d; name = n; mime = m; file = f;
        return Uri.parse("content://utv.app.share/" + Uri.encode(n));
    }

    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri u) { return mime; }

    @Override
    public Cursor query(Uri u, String[] proj, String sel, String[] args, String sort) {
        if (proj == null) proj = new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE};
        MatrixCursor c = new MatrixCursor(proj, 1);
        Object[] row = new Object[proj.length];
        for (int i = 0; i < proj.length; i++)
            row[i] = OpenableColumns.DISPLAY_NAME.equals(proj[i]) ? name : OpenableColumns.SIZE.equals(proj[i]) ? (Object) (file != null && file.exists() ? file.length() : (long) data.length) : null;
        c.addRow(row);
        return c;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri u, String mode) throws FileNotFoundException {
        java.io.File f = file;
        if (f != null && f.exists()) return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
        try {
            ParcelFileDescriptor[] p = ParcelFileDescriptor.createPipe();
            final byte[] d = data;
            new Thread(() -> {
                try (OutputStream o = new ParcelFileDescriptor.AutoCloseOutputStream(p[1])) { o.write(d); } catch (Exception ignored) {}
            }).start();
            return p[0];
        } catch (Exception e) { throw new FileNotFoundException(e.getMessage()); }
    }

    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String s, String[] a) { return 0; }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
}
