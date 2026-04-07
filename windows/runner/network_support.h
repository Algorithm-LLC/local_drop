#ifndef RUNNER_NETWORK_SUPPORT_H_
#define RUNNER_NETWORK_SUPPORT_H_

#include <optional>
#include <string>
#include <vector>

struct NetworkInterfaceInfo {
  std::string interface_name;
  std::string address;
  int prefix_length;
};

struct FirewallSetupInfo {
  std::string status;
  std::string message;
};

std::vector<NetworkInterfaceInfo> GetActiveInterfaces();
FirewallSetupInfo EnsureFirewallRulesInteractive();
std::optional<int> HandleRunnerCommand(const std::vector<std::string>& args);

#endif  // RUNNER_NETWORK_SUPPORT_H_
