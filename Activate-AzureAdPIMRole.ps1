#Requires -Module AzureAdPreview
#Requires -PSEdition Desktop

<#
.SYNOPSIS

Used to activate AzureAD Priveledge Identity Management (PIM) roles via powershell session

.DESCRIPTION

Builds and sends a request to activate an AzureAD Priveledge Identity Management (PIM) role
for either a specific Azure Subscription, or an Management Group.

.PARAMETER Username

Specify the username used to authenticate to AzureAd

.PARAMETER Type

Specify the type of resource for the PIM role to activated on. Either 'managementgroup' or 'subscription' is currently supported. 

.PARAMETER Name

Specify the name of the type parameter.

.PARAMETER Role

Specify the role that needs to be activated.  Either 'Contributor' or 'Owner' is currently supported

.PARAMETER Reason

Specify the reason for the request.

.PARAMETER RequestLength

Specify the number of hours the request should be active. Defaults to 8.

.PARAMETER SkipLogin

Allows the user to skip the AzureAD Login if their current PowerShell session is already logged in.

.INPUTS

None. You cannot pipe objecss to Activate-AzureAdPIMRole.ps1

.OUTPUTS 

Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRoleAssignmentRequestRequest
Activate-AzureAdPIMRole.ps1 returns the activation request object

.EXAMPLE

PS> Activate-AzureAdPIMRole -Username 'john.doe@contoso.com' -Type managementgroup -Name 'P-C00' -Role Contributor -Reason "Perform change work needed"

Activates Contributor role for a mangementgroup named 'P-C00'

.EXAMPLE

PS> Activate-AzureAdPIMRole -Username 'john.doe@contoso.com' -Type managementgroup -Name 'P-C00' -Role Owner -Reason "Perform change work needed" -SkipLogin

Activates Owner role for a mangementgroup named 'P-C00' and skips the AzureAd login

.EXAMPLE
PS> Activate-AzureAdPIMRole -Username 'john.doe@contoso.com' -Type subscription -Name 'PROD' -Role Contributor -Reason "Perform change work needed"

Activates the Contributor roles for a subscription named 'PROD'

#>

[CmdletBinding()]
Param(
    # User name is always required because we'll need to pull an AzureAdObject for the user
    [Parameter(Mandatory=$true)]
    [string]
    $Username,
    # Required to build the filter - Get-AzureADMSPriviledgedResource returns limited number of resources. This will allow us to return the ones we want
    [Parameter(Mandatory=$true)]
    [ValidateSet("managementgroup","subscription")]
    [string]
    $Type,
    # Parameter help description
    [Parameter(Mandatory=$true)]
    [String]
    $Name,
    # Role being activated, either Contributor or Owner
    [Parameter(Mandatory=$true)]
    [ValidateSet("Contributor","Owner")]
    [String]
    $Role,
    # Reason for the PIM request
    [Parameter(Mandatory=$true)]
    [string]
    $Reason,
    # Length of time for request in hours
    [Parameter(Mandatory=$false)]
    [ValidateRange(1,8)]
    [int]
    $RequestLength = 8,
    # Allows skipping of the login process
    [Parameter(Mandatory=$false)]
    [switch]
    $SkipLogin
)

# Login if needed
if (-not $SkipLogin){
    Try {
        Write-Verbose -Message 'Beginning login to AzureAD'
        Connect-AzureAD -AccountId $username -ErrorAction Stop
    } Catch {
        Write-Error -Message 'Not able to login to AzureAD, please try again'
        Throw $_
    }

    Write-Verbose -Message 'AzureAd login successful'
} else {
    Write-Verbose -Message 'Login to AzureAD Skipped by user switch. Assuming login has already occured'
}

Write-Verbose -Message "Retrieving AzureADUser Info"
Try {
    $userObject = Get-AzureADUser -Filter ("UserPrincipalName eq '" + $Username + "'") -ErrorAction Stop
} Catch {
    Write-Error -Message "Unable to retrieve user"
    Throw $_
}

if ($userObject.count -ne 1){
    Write-Error -Message "Found $($userObject).count user(s), expected 1"
    Throw "Unexpected user count"
}

Write-Verbose -Message "Retrieving AzureADMSPriviledgedResources object"
Try {
    $resource = Get-AzureADMSPrivilegedResource -ProviderId AzureResources -Filter ("Type eq '" + $type.ToLower() + "' and DisplayName eq '" + $name.ToUpper() + "'") -ErrorAction Stop
} Catch {
    Write-Error -Message "Error retrieving AzureADMSPriviledgedResources"
    throw $_
}

if ($resource.count -ne 1){
    Write-Error -Message "Found $($resource).count resource(s), expected 1"
    Throw "Unexpected resource count"
}

Write-Verbose -Message "Creating schedule object"
$scheduleObject = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedSchedule
$scheduleObject.Type = "Once"
$scheduleObject.StartDateTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$scheduleObject.EndDateTime = $scheduleObject.StartDateTime.AddHours($RequestLength)

Write-Verbose -Message "Retrieving AzureADMSPriveledgedRole object"
Try {
    $roleObject = Get-AzureADMSPrivilegedRoleDefinition -ProviderId 'AzureResources' -ResourceId $resource.Id -Filter ("DisplayName eq '" + $Role + "'") -ErrorAction Stop
} Catch {
    Write-Error -Message "Error retrieving AzureADMSPriveledgedRole object"
    Throw $_
}

if ($roleObject.count -ne 1){
    Write-Error -Message "Found $($roleObject).count role(s), expected 1"
    Throw "Unexpected Role count"
}

Write-Verbose -Message "Activating $role for $type $name"
Try {
    Open-AzureADMSPrivilegedRoleAssignmentRequest -ProviderId 'AzureResources' -ResourceId $resource.Id -Type UserAdd -SubjectId $userObject.ObjectId -RoleDefinitionId $roleObject.id -AssignmentState 'Active' -Schedule $scheduleObject -reason $reason -ErrorAction Stop
} Catch {
    Write-Error -Message "Error activating $role for $type $name"
    Throw $_
}
