<#
.SYNOPSIS
    IT Helpdesk User Offboarding Script

.DESCRIPTION
    Safely offboards a departing user by:
      1. Verifying the account exists
      2. Disabling the account
      3. Removing all security group memberships (retains Domain Users)
      4. Clearing the manager field
      5. Updating the account description with offboarding date and ticket reference
      6. Moving the account to OU=Disabled
      7. Logging all actions to a dated audit log

    The account is NOT deleted — best practice is to disable first and delete
    after your organisation's data retention period (typically 30 days).

.PARAMETER SAMAccountName
    The SAMAccountName (username) of the user to offboard

.PARAMETER TicketNumber
    The helpdesk ticket reference number. Included in logs and account description
    for audit trail. Defaults to "NO-TICKET" if not supplied.

.EXAMPLE
    .\offboard-user.ps1 -SAMAccountName "jsmith" -TicketNumber "INC0001234"

.EXAMPLE
    .\offboard-user.ps1 -SAMAccountName "abrown"

.NOTES
    Tested on: Windows Server 2022 with AD DS
    Requires:  ActiveDirectory PowerShell module
    Author:    Dave
#>

param(
    [Parameter(Mandatory = $true,  HelpMessage = "Username to offboard")]
    [string]$SAMAccountName,

    [Parameter(Mandatory = $false, HelpMessage = "Helpdesk ticket reference")]
    [string]$TicketNumber = "NO-TICKET"
)

# ── Configuration ──────────────────────────────────────────────────────────────
$DomainDN    = "DC=helpdesk,DC=lab"
$DisabledOU  = "OU=Disabled,OU=Users,$DomainDN"
$LogDirectory = "C:\Logs\Helpdesk"
$LogFile     = "$LogDirectory\offboarding_$(Get-Date -Format 'yyyy-MM-dd').log"
# ──────────────────────────────────────────────────────────────────────────────

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "[$timestamp] [$Level] [Ticket: $TicketNumber] $Message"
    Add-Content -Path $LogFile -Value $entry
    switch ($Level) {
        "INFO"  { Write-Host $entry -ForegroundColor Cyan }
        "WARN"  { Write-Host $entry -ForegroundColor Yellow }
        "ERROR" { Write-Host $entry -ForegroundColor Red }
    }
}

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

Write-Log "=================================================================="
Write-Log "Starting offboarding: $SAMAccountName"
Write-Log "=================================================================="

# ── Locate user ────────────────────────────────────────────────────────────────
try {
    $User = Get-ADUser -Identity $SAMAccountName `
              -Properties MemberOf, DisplayName, Department, Manager, Description, DistinguishedName `
              -ErrorAction Stop
    Write-Log "Found: $($User.DisplayName) | Dept: $($User.Department) | DN: $($User.DistinguishedName)"
} catch {
    Write-Log "User '$SAMAccountName' not found in Active Directory. Aborting." "ERROR"
    exit 1
}

# Check already disabled
if (-not $User.Enabled) {
    Write-Log "Account is already disabled. Proceeding with remaining steps." "WARN"
}

# ── Step 1: Disable account ────────────────────────────────────────────────────
try {
    Disable-ADAccount -Identity $SAMAccountName
    Write-Log "Step 1/5: Account disabled"
} catch {
    Write-Log "Step 1/5: Failed to disable account: $($_.Exception.Message)" "ERROR"
}

# ── Step 2: Remove all group memberships ───────────────────────────────────────
$Groups = $User.MemberOf
$RemovedCount = 0

if ($Groups.Count -eq 0) {
    Write-Log "Step 2/5: No group memberships to remove"
} else {
    foreach ($GroupDN in $Groups) {
        try {
            $GroupName = (Get-ADGroup -Identity $GroupDN).Name
            Remove-ADGroupMember -Identity $GroupDN -Members $SAMAccountName -Confirm:$false
            Write-Log "Step 2/5: Removed from group: $GroupName"
            $RemovedCount++
        } catch {
            Write-Log "Step 2/5: Could not remove from group '$GroupDN': $($_.Exception.Message)" "WARN"
        }
    }
    Write-Log "Step 2/5: Removed from $RemovedCount group(s)"
}

# ── Step 3: Clear manager field ────────────────────────────────────────────────
try {
    Set-ADUser -Identity $SAMAccountName -Manager $null
    Write-Log "Step 3/5: Manager field cleared"
} catch {
    Write-Log "Step 3/5: Could not clear manager field: $($_.Exception.Message)" "WARN"
}

# ── Step 4: Update account description ────────────────────────────────────────
$NewDesc = "OFFBOARDED $(Get-Date -Format 'yyyy-MM-dd') | Ticket: $TicketNumber"
try {
    Set-ADUser -Identity $SAMAccountName -Description $NewDesc
    Write-Log "Step 4/5: Description updated: $NewDesc"
} catch {
    Write-Log "Step 4/5: Could not update description: $($_.Exception.Message)" "WARN"
}

# ── Step 5: Move to Disabled OU ────────────────────────────────────────────────
try {
    # Verify Disabled OU exists
    Get-ADOrganizationalUnit -Identity $DisabledOU -ErrorAction Stop | Out-Null
    Move-ADObject -Identity $User.DistinguishedName -TargetPath $DisabledOU
    Write-Log "Step 5/5: Moved to Disabled OU: $DisabledOU"
} catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Log "Step 5/5: Disabled OU not found ($DisabledOU). Create it and move manually." "WARN"
} catch {
    Write-Log "Step 5/5: Failed to move account: $($_.Exception.Message)" "ERROR"
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Log "=================================================================="
Write-Log "Offboarding complete: $SAMAccountName"
Write-Log "=================================================================="

Write-Host ""
Write-Host "  [DONE] $SAMAccountName offboarded." -ForegroundColor Green
Write-Host ""
Write-Host "  Manual actions still required:" -ForegroundColor Yellow
Write-Host "  - Revoke email access / set out-of-office if needed" -ForegroundColor White
Write-Host "  - Delegate OneDrive/mailbox to manager if required" -ForegroundColor White
Write-Host "  - Revoke any VPN, remote access, or third-party app logins" -ForegroundColor White
Write-Host "  - Retrieve physical equipment (laptop, badge, keys)" -ForegroundColor White
Write-Host ""
Write-Host "  Account retained in OU=Disabled per data retention policy." -ForegroundColor Cyan
Write-Host "  Schedule deletion after your organisation's retention period." -ForegroundColor Cyan
Write-Host ""
