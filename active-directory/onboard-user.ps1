<#
.SYNOPSIS
    IT Helpdesk User Onboarding Script

.DESCRIPTION
    Creates a new Active Directory user account, assigns them to the correct
    departmental OU and security groups, sets a temporary password, and logs
    all actions to a dated log file.

    Designed for IT Helpdesk use in Windows Server / Active Directory environments.

.PARAMETER FirstName
    User's first name

.PARAMETER LastName
    User's last name

.PARAMETER Department
    Department name. Must match an existing OU under OU=Users (e.g. Finance, IT, HR, Operations)

.PARAMETER JobTitle
    User's job title (optional)

.PARAMETER Manager
    SAMAccountName of the user's line manager (optional)

.EXAMPLE
    .\onboard-user.ps1 -FirstName "Jane" -LastName "Smith" -Department "Finance" -JobTitle "Analyst"

.EXAMPLE
    .\onboard-user.ps1 -FirstName "Tom" -LastName "Hughes" -Department "IT" -JobTitle "Support Engineer" -Manager "jbrown"

.NOTES
    Tested on: Windows Server 2022 with AD DS
    Requires:  ActiveDirectory PowerShell module (RSAT or installed on DC)
    Author:    Dave
#>

param(
    [Parameter(Mandatory = $true,  HelpMessage = "User's first name")]
    [string]$FirstName,

    [Parameter(Mandatory = $true,  HelpMessage = "User's last name")]
    [string]$LastName,

    [Parameter(Mandatory = $true,  HelpMessage = "Department OU name (Finance, IT, HR, Operations)")]
    [string]$Department,

    [Parameter(Mandatory = $false, HelpMessage = "Job title (optional)")]
    [string]$JobTitle = "",

    [Parameter(Mandatory = $false, HelpMessage = "Manager's SAMAccountName (optional)")]
    [string]$Manager = ""
)

# ── Configuration ──────────────────────────────────────────────────────────────
# Update these values to match your domain
$DomainDN        = "DC=helpdesk,DC=lab"
$DefaultPassword = ConvertTo-SecureString "Welcome123!" -AsPlainText -Force
$LogDirectory    = "C:\Logs\Helpdesk"
$LogFile         = "$LogDirectory\onboarding_$(Get-Date -Format 'yyyy-MM-dd').log"
# ──────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    switch ($Level) {
        "INFO"  { Write-Host $entry -ForegroundColor Cyan }
        "WARN"  { Write-Host $entry -ForegroundColor Yellow }
        "ERROR" { Write-Host $entry -ForegroundColor Red }
    }
}

# Ensure log directory exists
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

Write-Log "=================================================================="
Write-Log "Starting onboarding: $FirstName $LastName | Dept: $Department"
Write-Log "=================================================================="

# ── Generate username ──────────────────────────────────────────────────────────
# Format: first initial + surname, lowercase, alphanumeric only, max 20 chars
$SAMAccountName = ($FirstName.Substring(0, 1) + $LastName).ToLower() -replace '[^a-z0-9]', ''
if ($SAMAccountName.Length -gt 20) { $SAMAccountName = $SAMAccountName.Substring(0, 20) }
$UPN         = "$SAMAccountName@helpdesk.lab"
$DisplayName = "$FirstName $LastName"
$OU          = "OU=$Department,OU=Users,$DomainDN"

Write-Log "Generated SAMAccountName: $SAMAccountName"
Write-Log "UPN: $UPN"
Write-Log "Target OU: $OU"

# ── Pre-flight checks ──────────────────────────────────────────────────────────

# Check for duplicate username
if (Get-ADUser -Filter { SamAccountName -eq $SAMAccountName } -ErrorAction SilentlyContinue) {
    Write-Log "User '$SAMAccountName' already exists. Aborting to avoid duplicates." "ERROR"
    exit 1
}

# Verify target OU exists
try {
    Get-ADOrganizationalUnit -Identity $OU -ErrorAction Stop | Out-Null
    Write-Log "Target OU verified: $OU"
} catch {
    Write-Log "OU '$OU' does not exist. Create it in AD before running this script." "ERROR"
    exit 1
}

# Verify manager exists (if supplied)
if ($Manager -ne "") {
    if (-not (Get-ADUser -Filter { SamAccountName -eq $Manager } -ErrorAction SilentlyContinue)) {
        Write-Log "Manager '$Manager' not found in AD. Proceeding without manager assignment." "WARN"
        $Manager = ""
    }
}

# ── Create user account ────────────────────────────────────────────────────────
try {
    $NewUserParams = @{
        Name                  = $DisplayName
        GivenName             = $FirstName
        Surname               = $LastName
        SamAccountName        = $SAMAccountName
        UserPrincipalName     = $UPN
        DisplayName           = $DisplayName
        Department            = $Department
        Title                 = $JobTitle
        Path                  = $OU
        AccountPassword       = $DefaultPassword
        Enabled               = $true
        ChangePasswordAtLogon = $true
    }
    if ($Manager -ne "") { $NewUserParams.Manager = $Manager }

    New-ADUser @NewUserParams
    Write-Log "Account created: $SAMAccountName"
} catch {
    Write-Log "Failed to create account: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ── Assign security groups ─────────────────────────────────────────────────────

# Departmental group (naming convention: GRP_<Department>)
$DeptGroup = "GRP_$Department"
try {
    Add-ADGroupMember -Identity $DeptGroup -Members $SAMAccountName
    Write-Log "Added to group: $DeptGroup"
} catch {
    Write-Log "Could not add to '$DeptGroup'. Does the group exist?" "WARN"
}

# All-staff group
try {
    Add-ADGroupMember -Identity "GRP_AllStaff" -Members $SAMAccountName
    Write-Log "Added to group: GRP_AllStaff"
} catch {
    Write-Log "Could not add to GRP_AllStaff." "WARN"
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Log "=================================================================="
Write-Log "Onboarding complete for $SAMAccountName"
Write-Log "Temporary password: Welcome123! (must change at first login)"
Write-Log "=================================================================="

Write-Host ""
Write-Host "  [DONE] Account ready." -ForegroundColor Green
Write-Host "  Username:  $SAMAccountName" -ForegroundColor White
Write-Host "  UPN:       $UPN" -ForegroundColor White
Write-Host "  Dept OU:   $OU" -ForegroundColor White
Write-Host "  Temp PW:   Welcome123! (user must change on first login)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  ACTION: Communicate credentials to user via secure channel (not email)." -ForegroundColor Cyan
