import CAdw
import Foundation

/// GTK's file dialog, for choosing one file or folder.
///
/// Adwaita for Swift has a file importer, but its C callback (`gtui_filedialog_open_finish` in its adwshim.c)
/// releases the chosen GFile before handing on the path it only borrowed from it. The path then arrives as freed
/// memory: usually still intact, sometimes garbage, and possibly another file's path (BUG-013). This takes its own
/// copy of the path before releasing anything.
enum FileChooser {
    enum Kind {
        case file, folder
    }

    /// Files of any of these MIME types, listed by `name` in the dialog's type menu.
    struct Filter {
        let mimeTypes: [String]
        let name: String?
    }

    /// Shows the dialog over the app's window and calls `chosen` once a file or folder is picked. Nothing happens
    /// when the dialog is dismissed.
    static func choose(_ kind: Kind, title: String, filters: [Filter], chosen: @escaping (URL) -> Void) {
        let dialog = gtk_file_dialog_new()
        gtk_file_dialog_set_title(dialog, title)
        if !filters.isEmpty {
            let store = g_list_store_new(gtk_file_filter_get_type())
            for filter in filters {
                let fileFilter = gtk_file_filter_new()
                for mimeType in filter.mimeTypes { gtk_file_filter_add_mime_type(fileFilter, mimeType) }
                if let name = filter.name {
                    gtk_file_filter_set_name(fileFilter, name)
                }
                g_list_store_append(store, UnsafeMutableRawPointer(fileFilter))
                g_object_unref(UnsafeMutableRawPointer(fileFilter))
            }
            gtk_file_dialog_set_filters(dialog, store)
            g_object_unref(UnsafeMutableRawPointer(store))
        }
        // The request and the dialog's own reference both pass to `finished`, which releases them.
        let request = Unmanaged.passRetained(Request(kind: kind, chosen: chosen)).toOpaque()
        switch kind {
        case .file: gtk_file_dialog_open(dialog, activeWindow(), nil, finished, request)
        case .folder: gtk_file_dialog_select_folder(dialog, activeWindow(), nil, finished, request)
        }
    }

    private final class Request {
        let kind: Kind
        let chosen: (URL) -> Void

        init(kind: Kind, chosen: @escaping (URL) -> Void) {
            self.kind = kind
            self.chosen = chosen
        }
    }

    /// The window the dialog belongs to, so it opens over Knobs and blocks it while open.
    private static func activeWindow() -> UnsafeMutablePointer<GtkWindow>? {
        guard let application = g_application_get_default() else { return nil }
        return gtk_application_get_active_window(
            UnsafeMutableRawPointer(application).assumingMemoryBound(to: GtkApplication.self))
    }

    private static let finished: GAsyncReadyCallback = { source, result, userData in
        guard let source, let userData else { return }
        let request = Unmanaged<Request>.fromOpaque(userData).takeRetainedValue()
        let dialog = OpaquePointer(source)
        defer { g_object_unref(UnsafeMutableRawPointer(source)) }

        var error: UnsafeMutablePointer<GError>?
        let file =
            switch request.kind {
            case .file: gtk_file_dialog_open_finish(dialog, result, &error)
            case .folder: gtk_file_dialog_select_folder_finish(dialog, result, &error)
            }
        guard let file else {
            if let error {
                let dismissed = Int32(GtkDialogError.GTK_DIALOG_ERROR_DISMISSED.rawValue)
                if g_error_matches(error, gtk_dialog_error_quark(), dismissed) == 0 {
                    report("the file dialog failed: \(String(cString: error.pointee.message))")
                }
                g_error_free(error)
            }
            return
        }
        defer { g_object_unref(UnsafeMutableRawPointer(file)) }
        // g_file_get_path returns a copy the caller owns, unlike the g_file_peek_path the library uses.
        guard let path = g_file_get_path(file) else {
            report("the chosen item has no local path")
            return
        }
        let url = URL(filePath: String(cString: path))
        g_free(path)
        request.chosen(url)
    }

    private static func report(_ problem: String) {
        FileHandle.standardError.write(Data("knobs: \(problem)\n".utf8))
    }
}
