#include "my_application.h"

#include <arpa/inet.h>
#include <flutter_linux/flutter_linux.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <cstdint>
#include <set>
#include <string>
#include <vector>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* network_channel;
  FlView* view;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

namespace {

struct NetworkInterfaceInfo {
  std::string interface_name;
  std::string address;
  int prefix_length;
};

std::string IPv4AddressToString(const in_addr& address) {
  char buffer[INET_ADDRSTRLEN];
  const char* result =
      inet_ntop(AF_INET, &address, buffer, sizeof(buffer));
  return result == nullptr ? std::string() : std::string(result);
}

bool IsLoopbackOrLinkLocal(const in_addr& address) {
  const auto host_order = ntohl(address.s_addr);
  const auto first_octet = static_cast<uint8_t>((host_order >> 24) & 0xff);
  const auto second_octet = static_cast<uint8_t>((host_order >> 16) & 0xff);
  return first_octet == 127 ||
         (first_octet == 169 && second_octet == 254);
}

int PrefixLengthFromNetmask(const sockaddr* netmask) {
  if (netmask == nullptr || netmask->sa_family != AF_INET) {
    return 24;
  }

  const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(netmask);
  uint32_t value = ntohl(ipv4->sin_addr.s_addr);
  int count = 0;
  while (value != 0) {
    count += static_cast<int>(value & 1u);
    value >>= 1;
  }
  return count;
}

std::vector<NetworkInterfaceInfo> GetActiveInterfaces() {
  std::vector<NetworkInterfaceInfo> interfaces;
  std::set<std::string> seen;

  ifaddrs* interface_addresses = nullptr;
  if (getifaddrs(&interface_addresses) != 0 || interface_addresses == nullptr) {
    return interfaces;
  }

  for (ifaddrs* current = interface_addresses; current != nullptr;
       current = current->ifa_next) {
    if (current->ifa_name == nullptr || current->ifa_addr == nullptr) {
      continue;
    }
    if ((current->ifa_flags & IFF_UP) == 0 ||
        (current->ifa_flags & IFF_LOOPBACK) != 0 ||
        current->ifa_addr->sa_family != AF_INET) {
      continue;
    }

    const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(current->ifa_addr);
    if (IsLoopbackOrLinkLocal(ipv4->sin_addr)) {
      continue;
    }

    const auto address = IPv4AddressToString(ipv4->sin_addr);
    if (address.empty()) {
      continue;
    }

    const auto prefix_length = PrefixLengthFromNetmask(current->ifa_netmask);
    const auto key = std::string(current->ifa_name) + "|" + address + "|" +
                     std::to_string(prefix_length);
    if (!seen.insert(key).second) {
      continue;
    }

    interfaces.push_back(NetworkInterfaceInfo{
        current->ifa_name,
        address,
        prefix_length,
    });
  }

  freeifaddrs(interface_addresses);
  return interfaces;
}

FlMethodResponse* BuildActiveInterfacesResponse() {
  g_autoptr(FlValue) interfaces = fl_value_new_list();
  for (const auto& interface_info : GetActiveInterfaces()) {
    g_autoptr(FlValue) item = fl_value_new_map();
    fl_value_set_string_take(
        item, "interfaceName",
        fl_value_new_string(interface_info.interface_name.c_str()));
    fl_value_set_string_take(
        item, "address", fl_value_new_string(interface_info.address.c_str()));
    fl_value_set_string_take(
        item, "prefixLength", fl_value_new_int(interface_info.prefix_length));
    fl_value_append_take(interfaces, fl_value_ref(item));
  }

  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_ref(interfaces)));
}

void NetworkMethodCallHandler(FlMethodChannel* channel,
                              FlMethodCall* method_call,
                              gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "acquireMulticastLock") == 0 ||
      g_strcmp0(method, "releaseMulticastLock") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "getActiveInterfaces") == 0) {
    response = BuildActiveInterfacesResponse();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond on localdrop/network: %s",
              error->message);
  }
}

void CreateChannels(MyApplication* self) {
  FlEngine* engine = fl_view_get_engine(self->view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->network_channel = fl_method_channel_new(
      messenger, "localdrop/network", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->network_channel,
                                            NetworkMethodCallHandler, self,
                                            nullptr);
}

}  // namespace

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
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "LocalDrop");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "LocalDrop");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_set_size_request(GTK_WIDGET(window), 330, 520);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  self->view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(self->view, &background_color);
  gtk_widget_show(GTK_WIDGET(self->view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(self->view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(self->view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(self->view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(self->view));
  CreateChannels(self);

  gtk_widget_grab_focus(GTK_WIDGET(self->view));
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
  g_clear_object(&self->network_channel);
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
