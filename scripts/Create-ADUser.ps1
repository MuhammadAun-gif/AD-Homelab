# Script to create a new AD user with the parameters passed in by the user


# Getting parameters for script from user
param(
    [Parameter(Mandatory=$true)]
    [string]$FirstName,

    [Parameter(Mandatory=$true)]
    [string]$Lastname,

    [Parameter(Mandatory=$true)]
    [string]$Username,

    [Parameter(Mandatory=$true)]
    [string]$OU,

    [Parameter(Mandatory=$true)]
    [string]$Domain
)

# Generate Random Password
$Password = -join((0x30..0x39)+(0x42..0x5A)+(0x61..0x7A) | Get-Random -Count 12 | FOrEach-Object{[char]$_})
Write-Host "Passowrd Generated as: $Password"

$SecurePassword = ($Password | ConvertTo-SecureString -AsPlainText -Force)

# make a call to New-ADUser to create the AD user
New-ADUser `
    -SamAccountName $Username `
    -UserPrincipalname "$Username@$Domain" `
    -Name "$FirstName $Lastname" `
    -Givenname $FirstName `
    -Surname $Lastname `
    -AccountPassword $SecurePassword `
    -Enabled $true `
    -Path "OU = $OU, DC = LAB, DC = local" `
    -PasswordNeverExpires $false `
    -ChangePasswordAtLogon $true