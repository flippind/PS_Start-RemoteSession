function Start-RemoteSession {
    [cmdletbinding(defaultparametersetname='None')]
    param (
        [Parameter(Mandatory=$False,ValueFromPipelinebyPropertyName=$True)]
            [ValidateScript({
                IF ( $_ -match ".*\\.*" -or [string]::IsNullOrEmpty($_)) { $true }
                ELSE { THROW "`$sessionUsername must be in the down-level format 'domain\username'" }
            })]
            [string]$sessionUsername,
        [Parameter(Mandatory=$False,ValueFromPipelinebyPropertyName=$True)]
            [ValidateScript({
                $inObj = $_
                if ( [string]::ISNullOrEmpty($inObj) ) { RETURN $true }
                elseif ( $inObj -match "^(?!:\/\/)(?=.{1,255}$)((.{1,63}\.){1,127}(?![0-9]*$)[a-z0-9-]+\.?)$" ) { 
                    if (Test-Connection $inObj -quiet) { RETURN $True }
                    else { Throw "$inObj was not reachable." }
                }
                else { Throw "`$sessionHost must be a valid FQDN" }
            })]
            [string]$sessionHost,
        [Parameter(Mandatory=$False)]
            [switch]$enter
    )
    <#
    .SYNOPSIS
    Initializes a PSSession to a given jumpHost
    
    .DESCRIPTION
    Initializes and enters a PSSession to a given jumpHost.  Intended for use when developing PowerShell for 
    functionality which requires server or privileged access.  Add to the profile specific to your chosen IDE.
    
    .PARAMETER sessionUsername
    Username to be used when initializing the remote session.  Must be in down-level format 'domain\username'.
    If this parameter is not specified, will first attempt to use $defaultRemoteDLUsername if defined.
    
    .PARAMETER sessionHost
    FQDN of the remote host to open a session to.  If this parameter is not specified, will first attempt to
    use $defaultRemoteHost if defined.

    .PARAMETER enter
    Enable this switch parameter to enter the session immediately.  When this is notspecified, the session can be
    called entered via 'Enter-PSSession -name "viaStart-RemoteSession"'.
    
    .INPUTS
    System.String $sessionUsername and $sessionHost may be passed by the pipeline by property name

    .OUTPUTS 
    System.Management.Automation.Runspaces.PSSession Returns the created PSSession object when not called with
    with the -enter parameter

    .EXAMPLE
    PS C:\> Start-RemoteSession -sessionUsername 'contoso\user' -sessionHost 'remotehost.contoso.com'
    Successfully opened background session to remotehost.contoso.com as contoso\user.  Session may be entered via
        Enter-PSSession -Name 'viaStart-RemoteSession'
    Please remember to terminate your session when unneeded, after exiting the session
        Remove-PSSession -name "viaStart-RemoteSession"

    Starts a remote session in the background to 'remotehost.contoso.com' as 'contoso\user'.

    .EXAMPLE
    PS C:\> Start-RemoteSession -sessionHost 'remotehost.contoso.com' -enter
    Please remember to terminate your session when unneeded, after exiting the session
        Remove-PSSession -name "viaStart-RemoteSession"

    Entering session to remotehost.contoso.com as contoso\user.  Exit the session via
        Exit-PSSession
    [remotehost.contoso.com]: PS C:\Users\user\Documents> 

    Starts and enters a remote session to 'remotehost.contoso.com'.  If $defaultRemoteDLUsername is not defined
    in a profile, user is prompted to provide the username to connect.  In this case, $defaultRemoteDLUsername 
    was defined in a profile to be 'contoso\user'
        
    .EXAMPLE
    PS U:\Git\LocalRepo\Powershell> Start-RemoteSession | enter-pssession
    Successfully opened background session to remotehost.contoso.com as contoso\user.  Session may be entered via
        Enter-PSSession -Name 'viaStart-RemoteSession'
    Please remember to terminate your session when unneeded, after exiting the session
        Remove-PSSession -name "viaStart-RemoteSession"
    [remotehost.contoso.com]: PS C:\Users\user\Documents> 

    Starts a remote session in the background, using the profile's $defaultRemoteDLUsername `contoso\user` and
    $defaultRemoteHost `remotehost.contoso.com`, then enters the session by name.  This is equivalent to 
    `Start-RemoteSession -enter`

    .EXAMPLE
    PS C:\> if (-not (Test-Path $profile)) { New-Item $profile }; psedit $profile;

    $defaultRemoteDLUsername = "contoso\username"
    $defaultRemoteHost = "remotehost.contoso.com"
    try {start-remotesession} catch [System.Management.Automation.CommandNotFoundException] {}

    Opens the PSProfile for the current user in the current host for editing.  The $defaultRemoteDLUsername and 
    $defaultRemoteHost variables are defined in the profile, and this cmdlet is called.  If this cmdlet is 
    found in a module when the profile is loaded (i.e. when the editor host is launched), a session will be opened
    in the background to 'remotehost.contoso.com' as 'contoso\username'.  Otherwise, no session is attempted nor
    error message displayed.

    .NOTES
    If this cmdlet is added within a module, you may have your current console host automatically start a session
    by calling this cmdlet within the console profile.
    #>

    BEGIN {
        if ($sessionUsername.length -le 0) {
            $sessionUserName = $defaultRemoteDLUsername
            while ($sessionUsername.length -le 0) {
                $sessionUsername = Read-Host "Enter the down-level username (domain\username) for the remote session"
            }
        }
        if ($sessionHost.length -le 0) {
            $sessionHost = $defaultRemoteHost
            while ($sessionHost.length -le 0) {
                $sessionHost = Read-Host "Enter the FQDN of the remote session host to connect to"
            }
        }
    }

    PROCESS {
        $CredentialPrompt = @{
            'Username' = $sessionUsername
            'Message' = "Please enter the user credentials for the remote session to $sessionhost"
            'Title' = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        while ($validCreds -ne $True) {
            $PSCredential = $host.UI.PromptForCredential($CredentialPrompt.Title,$CredentialPrompt.Message,`
                $CredentialPrompt.Username,$sessionHost)
            try {
                IF (-not $PSCredential) {
                    THROW [System.Management.Automation.ParameterBindingException]::new("User cancelled credential prompt.")
                }
                $jumpSession = New-PSSession -ComputerName $sessionHost -Credential $PSCredential `
                -Name 'viaStart-RemoteSession' -erroraction Stop
                $validCreds = $True
            }
            catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
                $Exception = New-Object System.Security.Authentication.InvalidCredentialException `
                    "The provided username or password is incorrect"
                $Category = [System.Management.Automation.ErrorCategory]::AuthenticationError
                $ErrorRecord = New-Object System.Management.Automation.ErrorRecord $Exception, `
                    'InvalidCredentials', $Category, $PSCredential
                $PSCmdlet.WriteError($ErrorRecord)
                $CredentialPrompt.message = "Please provide valid credentials for the remote session to $sessionhost"
            }
            catch [System.Management.Automation.ParameterBindingException] { THROW $Error[0] }
            catch {
                Write-Error "Unable to open PSSession to $sessionHost as $sessionUsername."
                THROW $Error[1]
            }
        }
    }

    END {
        Remove-Variable PSCredential
        IF ($jumpSession) {
            Write-Host @"
Please remember to terminate your session when unneeded, after exiting the session
    Remove-PSSession -name `"$($jumpSession.name)`"
"@
            if ($enter) { 
                Write-Host @"

Entering session to $sessionHost as $sessionUsername.  Exit the session via
    Exit-PSSession
"@
                Enter-PSSession -name $jumpSession.name 
            }
            else {
                Write-Host @"
Successfully opened background session to $sessionHost as $sessionUsername.  Session may be entered via
    `Enter-PSSession -Name '$($jumpSession.name)'
"@
            RETURN $jumpSession
            }
        }
    }
}