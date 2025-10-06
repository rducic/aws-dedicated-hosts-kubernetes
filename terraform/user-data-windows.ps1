<powershell>
# Windows Server 2022 Configuration Script for RDP Bastion Host

# Set Administrator password
$Password = ConvertTo-SecureString "${admin_password}" -AsPlainText -Force
$UserAccount = Get-LocalUser -Name "Administrator"
$UserAccount | Set-LocalUser -Password $Password

# Enable RDP
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# Configure Windows Firewall for RDP
New-NetFirewallRule -DisplayName "Allow RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install useful tools
choco install -y putty
choco install -y winscp
choco install -y notepadplusplus
choco install -y googlechrome
choco install -y 7zip

# Install AWS CLI
choco install -y awscli

# Install kubectl
choco install -y kubernetes-cli

# Create desktop shortcuts
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$Home\Desktop\PuTTY.lnk")
$Shortcut.TargetPath = "C:\ProgramData\chocolatey\bin\putty.exe"
$Shortcut.Save()

$Shortcut = $WshShell.CreateShortcut("$Home\Desktop\WinSCP.lnk")
$Shortcut.TargetPath = "C:\Program Files (x86)\WinSCP\WinSCP.exe"
$Shortcut.Save()

# Create a batch file for easy K8s access
$BatchContent = @"
@echo off
echo Kubernetes Cluster Management
echo ============================
echo.
echo Master Node IP: MASTER_IP_PLACEHOLDER
echo.
echo To connect to master node:
echo putty -ssh -i your-key.ppk ec2-user@MASTER_IP_PLACEHOLDER
echo.
echo To access Kubernetes Dashboard:
echo kubectl proxy --address='0.0.0.0' --port=8080 --accept-hosts='.*'
echo Then open: http://localhost:8080/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
echo.
pause
"@

$BatchContent | Out-File -FilePath "$Home\Desktop\K8s-Access.bat" -Encoding ASCII

# Configure timezone
tzutil /s "Pacific Standard Time"

# Disable IE Enhanced Security Configuration
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0

# Create welcome message
$WelcomeMessage = @"
Welcome to the Kubernetes Management Bastion Host!

This Windows Server provides secure access to your Kubernetes cluster.

Installed Tools:
- PuTTY (SSH client)
- WinSCP (File transfer)
- AWS CLI
- kubectl (Kubernetes CLI)
- Chrome browser

Security Features:
- RDP access restricted to your IP only
- Private network access to K8s nodes
- No direct internet access for worker nodes

Use the desktop shortcuts to access your tools.
Check K8s-Access.bat for connection details.
"@

$WelcomeMessage | Out-File -FilePath "$Home\Desktop\README.txt" -Encoding UTF8

# Restart to apply all changes
Write-Host "Configuration complete. System will restart in 60 seconds..."
Start-Sleep -Seconds 60
Restart-Computer -Force
</powershell>