#include "network_support.h"

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <netfw.h>
#include <shellapi.h>

#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#include <cwctype>

#include "utils.h"

namespace {

constexpr wchar_t kDiscoveryRuleName[] = L"LocalDrop Discovery (UDP)";
constexpr wchar_t kTransferRuleName[] = L"LocalDrop Transfer (TCP)";
constexpr wchar_t kDiscoveryRulePorts[] = L"5353";
constexpr wchar_t kTransferRulePorts[] = L"41937,41938";

std::wstring GetCurrentExecutablePath() {
  std::wstring path(MAX_PATH, L'\0');
  DWORD length = 0;
  while (true) {
    length = GetModuleFileNameW(nullptr, path.data(),
                                static_cast<DWORD>(path.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (length < path.size() - 1) {
      path.resize(length);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

std::wstring ToLower(std::wstring value) {
  for (auto& ch : value) {
    ch = static_cast<wchar_t>(towlower(ch));
  }
  return value;
}

bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elevation = {};
  DWORD size = 0;
  const bool elevated =
      GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation),
                          &size) != FALSE &&
      elevation.TokenIsElevated != 0;
  CloseHandle(token);
  return elevated;
}

FirewallSetupInfo MakeFirewallInfo(const std::string& status,
                                   const std::string& message = "") {
  return FirewallSetupInfo{status, message};
}

bool RuleMatches(INetFwRules* rules, const wchar_t* rule_name, long protocol,
                 const std::wstring& executable_path,
                 const wchar_t* expected_ports) {
  INetFwRule* rule = nullptr;
  BSTR rule_name_bstr = SysAllocString(rule_name);
  const HRESULT hr = rules->Item(rule_name_bstr, &rule);
  SysFreeString(rule_name_bstr);
  if (FAILED(hr) || rule == nullptr) {
    return false;
  }

  long actual_protocol = 0;
  BSTR application_name = nullptr;
  BSTR local_ports = nullptr;
  NET_FW_RULE_DIRECTION direction = NET_FW_RULE_DIR_OUT;
  NET_FW_ACTION action = NET_FW_ACTION_BLOCK;
  VARIANT_BOOL enabled = VARIANT_FALSE;
  long profiles = 0;

  const bool success =
      SUCCEEDED(rule->get_Protocol(&actual_protocol)) &&
      SUCCEEDED(rule->get_ApplicationName(&application_name)) &&
      SUCCEEDED(rule->get_LocalPorts(&local_ports)) &&
      SUCCEEDED(rule->get_Direction(&direction)) &&
      SUCCEEDED(rule->get_Action(&action)) &&
      SUCCEEDED(rule->get_Enabled(&enabled)) &&
      SUCCEEDED(rule->get_Profiles(&profiles));

  const std::wstring actual_app =
      application_name == nullptr ? std::wstring() : application_name;
  const std::wstring actual_ports =
      local_ports == nullptr ? std::wstring() : local_ports;

  if (application_name != nullptr) {
    SysFreeString(application_name);
  }
  if (local_ports != nullptr) {
    SysFreeString(local_ports);
  }
  rule->Release();

  return success && actual_protocol == protocol &&
         ToLower(actual_app) == ToLower(executable_path) &&
         ToLower(actual_ports) == ToLower(expected_ports) &&
         direction == NET_FW_RULE_DIR_IN &&
         action == NET_FW_ACTION_ALLOW &&
         enabled == VARIANT_TRUE &&
         profiles == NET_FW_PROFILE2_ALL;
}

HRESULT AddFirewallRule(INetFwRules* rules, const wchar_t* rule_name,
                        const wchar_t* description, long protocol,
                        const std::wstring& executable_path,
                        const wchar_t* ports) {
  BSTR rule_name_bstr = SysAllocString(rule_name);
  rules->Remove(rule_name_bstr);
  SysFreeString(rule_name_bstr);

  INetFwRule* rule = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(NetFwRule), nullptr,
                                CLSCTX_INPROC_SERVER, __uuidof(INetFwRule),
                                reinterpret_cast<void**>(&rule));
  if (FAILED(hr) || rule == nullptr) {
    return FAILED(hr) ? hr : E_POINTER;
  }

  BSTR name_bstr = SysAllocString(rule_name);
  BSTR description_bstr = SysAllocString(description);
  BSTR executable_bstr = SysAllocString(executable_path.c_str());
  BSTR ports_bstr = SysAllocString(ports);

  hr = rule->put_Name(name_bstr);
  if (SUCCEEDED(hr)) {
    hr = rule->put_Description(description_bstr);
  }
  if (SUCCEEDED(hr)) {
    hr = rule->put_ApplicationName(executable_bstr);
  }
  if (SUCCEEDED(hr)) {
    hr = rule->put_Protocol(protocol);
  }
  if (SUCCEEDED(hr)) {
    hr = rule->put_LocalPorts(ports_bstr);
  }
  if (SUCCEEDED(hr)) {
    hr = rule->put_Direction(NET_FW_RULE_DIR_IN);
  }
  if (SUCCEEDED(hr)) {
    hr = rule->put_Action(NET_FW_ACTION_ALLOW);
  }
  if (SUCCEEDED(hr)) {
    hr = rule->put_Enabled(VARIANT_TRUE);
  }
  if (SUCCEEDED(hr)) {
    hr = rule->put_Profiles(NET_FW_PROFILE2_ALL);
  }
  if (SUCCEEDED(hr)) {
    hr = rules->Add(rule);
  }

  SysFreeString(name_bstr);
  SysFreeString(description_bstr);
  SysFreeString(executable_bstr);
  SysFreeString(ports_bstr);
  rule->Release();
  return hr;
}

FirewallSetupInfo ConfigureFirewallRulesForExecutable(
    const std::wstring& executable_path) {
  const HRESULT init_hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(init_hr) && init_hr != RPC_E_CHANGED_MODE) {
    return MakeFirewallInfo("failed", "Failed to initialize COM.");
  }
  const bool should_uninitialize = SUCCEEDED(init_hr);

  INetFwPolicy2* policy = nullptr;
  HRESULT hr = CoCreateInstance(__uuidof(NetFwPolicy2), nullptr,
                                CLSCTX_INPROC_SERVER, __uuidof(INetFwPolicy2),
                                reinterpret_cast<void**>(&policy));
  if (FAILED(hr) || policy == nullptr) {
    if (should_uninitialize) {
      CoUninitialize();
    }
    return MakeFirewallInfo("failed", "Failed to access Windows Firewall.");
  }

  INetFwRules* rules = nullptr;
  hr = policy->get_Rules(&rules);
  if (FAILED(hr) || rules == nullptr) {
    policy->Release();
    if (should_uninitialize) {
      CoUninitialize();
    }
    return MakeFirewallInfo("failed", "Failed to enumerate firewall rules.");
  }

  const bool has_discovery_rule =
      RuleMatches(rules, kDiscoveryRuleName, NET_FW_IP_PROTOCOL_UDP,
                  executable_path, kDiscoveryRulePorts);
  const bool has_transfer_rule =
      RuleMatches(rules, kTransferRuleName, NET_FW_IP_PROTOCOL_TCP,
                  executable_path, kTransferRulePorts);
  if (has_discovery_rule && has_transfer_rule) {
    rules->Release();
    policy->Release();
    if (should_uninitialize) {
      CoUninitialize();
    }
    return MakeFirewallInfo("alreadyConfigured");
  }

  hr = AddFirewallRule(rules, kDiscoveryRuleName,
                       L"Allow LocalDrop mDNS discovery traffic.",
                       NET_FW_IP_PROTOCOL_UDP, executable_path,
                       kDiscoveryRulePorts);
  if (SUCCEEDED(hr)) {
    hr = AddFirewallRule(rules, kTransferRuleName,
                         L"Allow LocalDrop TCP transfer traffic.",
                         NET_FW_IP_PROTOCOL_TCP, executable_path,
                         kTransferRulePorts);
  }

  rules->Release();
  policy->Release();
  if (should_uninitialize) {
    CoUninitialize();
  }

  if (FAILED(hr)) {
    return MakeFirewallInfo("failed", "Failed to create Windows firewall rules.");
  }
  return MakeFirewallInfo("configuredNow");
}

FirewallSetupInfo RunElevatedFirewallHelper(const std::wstring& executable_path) {
  const std::wstring current_executable = GetCurrentExecutablePath();
  if (current_executable.empty()) {
    return MakeFirewallInfo("failed", "Unable to resolve the LocalDrop executable path.");
  }

  std::wstringstream arguments;
  arguments << L"--localdrop-firewall-helper "
            << L"--localdrop-exe=\"" << executable_path << L"\"";
  const std::wstring arguments_text = arguments.str();

  SHELLEXECUTEINFOW execute_info = {};
  execute_info.cbSize = sizeof(execute_info);
  execute_info.fMask = SEE_MASK_NOCLOSEPROCESS;
  execute_info.lpVerb = L"runas";
  execute_info.lpFile = current_executable.c_str();
  execute_info.lpParameters = arguments_text.c_str();
  execute_info.nShow = SW_HIDE;

  if (!ShellExecuteExW(&execute_info)) {
    const DWORD error = GetLastError();
    if (error == ERROR_CANCELLED) {
      return MakeFirewallInfo(
          "denied",
          "Administrator approval was denied for the Windows firewall update.");
    }
    return MakeFirewallInfo("failed",
                            "Unable to launch the elevated firewall helper.");
  }

  WaitForSingleObject(execute_info.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(execute_info.hProcess, &exit_code);
  CloseHandle(execute_info.hProcess);

  if (exit_code == 0) {
    return MakeFirewallInfo("configuredNow");
  }
  return MakeFirewallInfo("failed", "The elevated firewall helper did not complete successfully.");
}

std::wstring GetArgumentValue(const std::vector<std::string>& args,
                              const std::string& prefix) {
  for (const auto& arg : args) {
    if (arg.rfind(prefix, 0) == 0) {
      return Utf16FromUtf8(arg.substr(prefix.size()));
    }
  }
  return std::wstring();
}

}  // namespace

std::vector<NetworkInterfaceInfo> GetActiveInterfaces() {
  ULONG buffer_size = 15000;
  std::vector<unsigned char> buffer(buffer_size);
  PIP_ADAPTER_ADDRESSES adapters =
      reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data());

  ULONG flags = GAA_FLAG_INCLUDE_PREFIX;
  ULONG result = GetAdaptersAddresses(AF_INET, flags, nullptr, adapters,
                                      &buffer_size);
  if (result == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(buffer_size);
    adapters = reinterpret_cast<PIP_ADAPTER_ADDRESSES>(buffer.data());
    result = GetAdaptersAddresses(AF_INET, flags, nullptr, adapters,
                                  &buffer_size);
  }
  if (result != NO_ERROR) {
    return {};
  }

  std::set<std::string> seen;
  std::vector<NetworkInterfaceInfo> interfaces;
  for (PIP_ADAPTER_ADDRESSES adapter = adapters; adapter != nullptr;
       adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp ||
        adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK ||
        adapter->IfType == IF_TYPE_TUNNEL) {
      continue;
    }

    const std::string interface_name = Utf8FromUtf16(adapter->FriendlyName);
    if (interface_name.empty()) {
      continue;
    }

    for (PIP_ADAPTER_UNICAST_ADDRESS address = adapter->FirstUnicastAddress;
         address != nullptr; address = address->Next) {
      if (address->Address.lpSockaddr == nullptr ||
          address->Address.lpSockaddr->sa_family != AF_INET) {
        continue;
      }

      auto* ipv4 =
          reinterpret_cast<sockaddr_in*>(address->Address.lpSockaddr);
      char text[INET_ADDRSTRLEN] = {};
      if (InetNtopA(AF_INET, &ipv4->sin_addr, text, INET_ADDRSTRLEN) ==
          nullptr) {
        continue;
      }

      const std::string ip_address = text;
      if (ip_address.rfind("127.", 0) == 0 ||
          ip_address.rfind("169.254.", 0) == 0) {
        continue;
      }

      const int prefix_length =
          static_cast<int>(address->OnLinkPrefixLength);
      const std::string key = interface_name + "|" + ip_address + "|" +
                              std::to_string(prefix_length);
      if (!seen.insert(key).second) {
        continue;
      }

      interfaces.push_back(
          NetworkInterfaceInfo{interface_name, ip_address, prefix_length});
    }
  }

  return interfaces;
}

FirewallSetupInfo EnsureFirewallRulesInteractive() {
  const std::wstring executable_path = GetCurrentExecutablePath();
  if (executable_path.empty()) {
    return MakeFirewallInfo("failed", "Unable to resolve the LocalDrop executable path.");
  }

  const FirewallSetupInfo current_status =
      ConfigureFirewallRulesForExecutable(executable_path);
  if (current_status.status == "alreadyConfigured" ||
      current_status.status == "configuredNow") {
    return current_status;
  }

  if (current_status.status == "failed" && IsProcessElevated()) {
    return current_status;
  }

  if (IsProcessElevated()) {
    return current_status;
  }

  return RunElevatedFirewallHelper(executable_path);
}

std::optional<int> HandleRunnerCommand(const std::vector<std::string>& args) {
  bool is_firewall_helper = false;
  for (const auto& arg : args) {
    if (arg == "--localdrop-firewall-helper") {
      is_firewall_helper = true;
      break;
    }
  }
  if (!is_firewall_helper) {
    return std::nullopt;
  }

  std::wstring executable_path =
      GetArgumentValue(args, "--localdrop-exe=");
  if (executable_path.empty()) {
    executable_path = GetCurrentExecutablePath();
  }
  const FirewallSetupInfo result =
      ConfigureFirewallRulesForExecutable(executable_path);
  return result.status == "alreadyConfigured" ||
                 result.status == "configuredNow"
             ? 0
             : 1;
}
