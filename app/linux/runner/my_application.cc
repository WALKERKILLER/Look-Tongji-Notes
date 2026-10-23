#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  // "look/links" channel: lookstudio:// links handed to the app by the
  // desktop (see app/lib/core/deep_links.dart).
  FlMethodChannel* links;
  // Links received before Dart asked for them with "initial".
  GPtrArray* pending_links;
  gboolean dart_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Answers "initial" with the links that arrived before Dart was listening.
static void links_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;
  if (g_strcmp0(fl_method_call_get_name(call), "initial") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (guint i = 0; i < self->pending_links->len; i++) {
      fl_value_append_take(
          list, fl_value_new_string(static_cast<const gchar*>(
                    g_ptr_array_index(self->pending_links, i))));
    }
    g_ptr_array_set_size(self->pending_links, 0);
    self->dart_ready = TRUE;
    fl_method_call_respond_success(call, list, &error);
  } else {
    fl_method_call_respond_not_implemented(call, &error);
  }
  if (error != nullptr) {
    g_warning("look/links: %s", error->message);
  }
}

// Passes a link to Dart, or keeps it until Dart asks.
static void deliver_link(MyApplication* self, const gchar* uri) {
  if (self->dart_ready && self->links != nullptr) {
    g_autoptr(FlValue) arg = fl_value_new_string(uri);
    fl_method_channel_invoke_method(self->links, "open", arg, nullptr, nullptr,
                                    nullptr);
  } else {
    g_ptr_array_add(self->pending_links, g_strdup(uri));
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // A second launch reaches the running instance here: just raise it.
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  // Cleared when the window goes away, so a late link never touches it.
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->window));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "look_studio");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "look_studio");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->links = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "look/links",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->links, links_method_cb, self,
                                            nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name; lookstudio://
  // links are opened rather than passed to Dart.
  g_autoptr(GPtrArray) args = g_ptr_array_new();
  g_autoptr(GPtrArray) links = g_ptr_array_new_with_free_func(g_object_unref);
  for (gchar** arg = *arguments + 1; *arg != nullptr; arg++) {
    if (g_str_has_prefix(*arg, "lookstudio:")) {
      g_ptr_array_add(links, g_file_new_for_uri(*arg));
    } else {
      g_ptr_array_add(args, *arg);
    }
  }
  g_ptr_array_add(args, nullptr);
  self->dart_entrypoint_arguments =
      g_strdupv(reinterpret_cast<gchar**>(args->pdata));

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // When another instance is running these are forwarded to it over D-Bus
  // and this process exits.
  if (links->len > 0) {
    g_application_open(application, reinterpret_cast<GFile**>(links->pdata),
                       links->len, "");
  } else {
    g_application_activate(application);
  }
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::open, for lookstudio:// links.
static void my_application_open(GApplication* application, GFile** files,
                                gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  g_application_activate(application);
  for (gint i = 0; i < n_files; i++) {
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    deliver_link(self, uri);
  }
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->links);
  g_clear_pointer(&self->pending_links, g_ptr_array_unref);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_links = g_ptr_array_new_with_free_func(g_free);
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));
}
