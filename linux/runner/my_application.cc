#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

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
  // Titulo de ventana sobreescribible por entorno (VULP_WINDOW_TITLE). Sirve
  // para que el compositor pueda distinguir la instancia de desarrollo del
  // binario normal: el harness del MCP se lanza con "vulpedebug" en el
  // titulo, y una regla de ventana de niri lo abre en otra pantalla sin robar
  // el foco, para poder seguir usando la maquina mientras corre.
  //
  // Sin la variable el titulo es el de siempre, asi que produccion no cambia.
  const gchar* titulo_entorno = g_getenv("VULP_WINDOW_TITLE");
  const gchar* titulo = (titulo_entorno != nullptr && *titulo_entorno != '\0')
                            ? titulo_entorno
                            : "VulpTiketing";

  // Se fija en la ventana SIEMPRE (no solo en la barra de encabezado): el
  // titulo que ve el compositor es el del toplevel, y es contra ese que
  // matchea la regla de niri.
  gtk_window_set_title(window, titulo);

  // Sin marco cuando se pide (VULP_SIN_MARCO=1). Es para grabar: la barra de
  // titulo del escritorio en medio de un tutorial de una app de telefono se ve
  // como lo que es, un pegote, y recortarla despues en el editor obliga a
  // acertar el recorte en cada toma.
  const gchar* sin_marco = g_getenv("VULP_SIN_MARCO");
  if (sin_marco != nullptr && *sin_marco == '1') {
    use_header_bar = FALSE;
    gtk_window_set_decorated(window, FALSE);
  }

  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, titulo);
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }

  // Tamano de ventana sobreescribible (VULP_VENTANA="360x770"), en pixeles
  // LOGICOS.
  //
  // Existe para poder dar a la ventana la forma de un telefono y grabar
  // tutoriales que se vean como lo que el personal va a usar. Los aparatos del
  // negocio miden 1080x2312 fisicos a 480 dpi, o sea 360x770 logicos — y son
  // esos 360 los que disparan la composicion compacta (decision 0026).
  //
  // Para que ademas grabe a 1080 de ancho hace falta GDK_SCALE=3 en el entorno:
  // sin el, en Linux el factor de escala es 1 y 360 logicos son 360 pixeles.
  //
  // Esto es del runner de Linux, que NO entra en el APK: la app publicada no
  // compila este archivo.
  int ancho = 1280;
  int alto = 720;
  const gchar* ventana = g_getenv("VULP_VENTANA");
  if (ventana != nullptr) {
    int a = 0;
    int b = 0;
    if (sscanf(ventana, "%dx%d", &a, &b) == 2 && a > 0 && b > 0) {
      ancho = a;
      alto = b;
    } else {
      g_warning("VULP_VENTANA=\"%s\" no tiene la forma ANCHOxALTO; se ignora", ventana);
    }
  }
  gtk_window_set_default_size(window, ancho, alto);

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

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
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
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
