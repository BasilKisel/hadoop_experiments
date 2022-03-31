<#
.SYNOPSIS
    Creates pseudo-distributed HADOOP cluster in Ubuntu distibution inside WSL.

.DESCRIPTION
    The script enables WSL and imports Ubuntu discributioin (20.04 Focal Fossa) inside WSL2.
    Then, the script transform the spinned distibution:
        * updates packages,
        * installs JDK version 8,
        * installs HADOOP version ??,
        * configure pseudo-distributed cluster.

.NOTES
    The link to the official tutorial: https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-common/SingleCluster.html

.PARAMETER SkipWslInstallation
    Skips enabling "VirtualMachinePlatform" and "Microsoft-Windows-Subsystem-Linux" Windows optional features. Allows to use the script without administrative privileges.

.PARAMETER PathToUbuntuDistro
    Specifies the path to Ububtu distro archive to be used or downloaded. If it's not specified, the temp path will be used.

.PARAMETER WslDistroName
    Provides a name for a distro to be imported into WSL or to be used as is.

.PARAMETER ReimportDistro
    Specify to remove the existing distro by provided 'WslDistroName' parameter before any attempts are made to import a new one. Cannot be specified with the SkipDistroImport switch.

.PARAMETER SkipDistroImport
    Skips importing Ubuntu image in WSL. Correct distro name must be provided by 'WslDistroName' parameter. Cannot be specified with the ReimportDistro switch.

.PARAMETER WslDistroInstallLocation
    Specifies the place to install WSL distribution. Default is "wsl-distros" directory in the user's home path.

.PARAMETER Batch
    Specify no intections with the user.

#>

param(
    [switch]$Batch,
    [switch]$SkipWslInstallation,
    [String]$PathToUbuntuDistro = $null,
    [switch]$SkipDistroImport,
    [switch]$ReimportDistro,
    [String]$WslDistroName = 'PseudoDistributedHadoopOnUbuntuFocalFossa',
    [String]$WslDistroInstallLocation = "$env:HOMEPATH\wsl-distros\$WslDistroName"
)

if ($SkipWslInstallation -and $ReimportDistro)
{
    Write-Warning 'SkipWslInstallation and ReimportDistro parameters are mutually exclusive. Please, provide the correct one.'
    break
}

### Constants ####################################################################################################

$DebugPreference = "Continue"
$FocalFossaWslImageUri = 'https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64-wsl.rootfs.tar.gz'

$Batch = $true
$SkipWslInstallation = $true
$SkipDistroImport = $true
$PathToUbuntuDistro = 'C:\v.kisel\wsl\images\ubuntu\focal-fossa_20.04.LTS\focal-server-cloudimg-amd64-wsl.rootfs.tar.gz'

### Enable WSL ###################################################################################################

if (-not $SkipWslInstallation)
{
    if (-not ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity])::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        Write-Warning "Rerun this script with administrative privileges to setup WSL or skip this step with the switch -SkipWslInstallation."
        break
    }
    elseif (-not $(Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux").State -eq ([Microsoft.Dism.Commands.FeatureState]"Enabled"))
    {
        $restartNeeded = ($(Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform","Microsoft-Windows-Subsystem-Linux").RestartNeeded)
        Write-Host "WSL successfully installed."
        if ($restartNeeded)
        {
            Write-Warning "Please, restart your PC and rerun this script."
            break
        }
    }
}

### Download Ubuntu distro #######################################################################################

if (-not $SkipDistroImport)
{
    if ([System.IO.File]::Exists($PathToUbuntuDistro))
    {
        Write-Host "'$PathToUbuntuDistro' recognized as a Ubuntu image."
    }
    else
    {
        if (-not $PathToUbuntuDistro)
        {
            $PathToUbuntuDistro = (New-TemporaryFile).FullName
            Write-Host "Created a temp file for PathToUbuntuDistro = '$PathToUbuntuDistro'"
        }
        else
        {
            if (-not ($PathToUbuntuDistro -like '*.tar.gz' -or $PathToUbuntuDistro -like '*.tgz'))
            {
                Write-Warning "'$PathToUbuntuDistro' doesn't have '.tar.gz' or '.tgz' extension. '.tar.gz' will be appended to the file name."
                $PathToUbuntuDistro = $PathToUbuntuDistro + '.tar.gz'
            }
        }
        Invoke-WebRequest -Uri $FocalFossaWslImageUri -OutFile $PathToUbuntuDistro
    }
}

### Spin up a distro #############################################################################################

if (-not $SkipDistroImport)
{
    if ($(wsl -l -q).Split("`n") | Where-Object {$_ -eq $WslDistroName})
    {
        if ($ReimportDistro)
        {
            wsl -t $WslDistroName | Write-Debug
            wsl --unregister $WslDistroName | Write-Debug
        }
        else
        {
            Write-Warning "'$WslDistroName' exists. The script stopped to prevent data loss. Perhaps, you want to replace the distro with the switch 'ReimportDistro'?"
            break
        }
    }
    New-Item -Path $WslDistroInstallLocation -ItemType Directory -ErrorAction SilentlyContinue | Write-Debug
    wsl --import $WslDistroName $WslDistroInstallLocation $PathToUbuntuDistro --version 2 | Write-Debug
}

### Install software onto the spinned distro #####################################################################

wsl -d $WslDistroName -- apt-get update | Write-Debug
wsl -d $WslDistroName -- apt-get upgrade -y | Write-Debug
$ErrorActionPreference = 'SilentlyContinue'
wsl -d $WslDistroName -- apt-get install -y ssh pdsh openjdk-8-jre openjdk-8-jdk | Write-Debug
$ErrorActionPreference = 'Continue'

function removeHadoopTmpFiles([String]$WslDistroName)
{
    wsl -d $WslDistroName -- cd /tmp "&&" rm -f ./all_known_keys.gpg ./hadoop_sign_cleartext ./hadoop_keys ./hadoop-3.3.2.tar.gz.sha512 ./hadoop-3.3.2.tar.gz.asc # ./hadoop-3.3.2.tar.gz
}
$hadoop332TarGzUri = 'https://dlcdn.apache.org/hadoop/common/hadoop-3.3.2/hadoop-3.3.2.tar.gz'
$hadoop332TarGzAscUri = 'https://dlcdn.apache.org/hadoop/common/hadoop-3.3.2/hadoop-3.3.2.tar.gz.asc'
$hadoop332TarGzSha512Uri = 'https://dlcdn.apache.org/hadoop/common/hadoop-3.3.2/hadoop-3.3.2.tar.gz.sha512'
$hadoopKeysUri = 'https://dlcdn.apache.org/hadoop/common/KEYS'
removeHadoopTmpFiles($WslDistroName)
#wsl -d $WslDistroName -- curl -o /tmp/hadoop-3.3.2.tar.gz -s $hadoop332TarGzUri
wsl -d $WslDistroName -- curl -o /tmp/hadoop-3.3.2.tar.gz.sha512 -s $hadoop332TarGzSha512Uri
$hadoopDistroSha512CheckResultTxt = $(wsl -d $WslDistroName -- cd /tmp "&&" sha512sum --check --warn ./hadoop-3.3.2.tar.gz.sha512)
wsl -d $WslDistroName -- curl -o /tmp/hadoop-3.3.2.tar.gz.asc -s $hadoop332TarGzAscUri
wsl -d $WslDistroName -- curl -o /tmp/hadoop_keys -s $hadoopKeysUri
$ErrorActionPreference = 'SilentlyContinue' # Due to some missing keys
wsl -d $WslDistroName -- gpg --import /tmp/hadoop_keys | Write-Debug
$ErrorActionPreference = 'Continue'
wsl -d $WslDistroName -- rm -f /tmp/all_known_keys.gpg /tmp/hadoop_sign_cleartext
wsl -d $WslDistroName -- gpg --export --output /tmp/all_known_keys.gpg | Write-Debug
wsl -d $WslDistroName -- cd /tmp "&&" gpgv --log-file ./hadoop_sign_cleartext --keyring ./all_known_keys.gpg ./hadoop-3.3.2.tar.gz.asc ./hadoop-3.3.2.tar.gz
$hadoopDistroSignatureCleartext = $(wsl -d $WslDistroName -- cat /tmp/hadoop_sign_cleartext)
$hadoopDistroSignerGoogleQuery = 'https://www.google.com/search?q="' + $(wsl -d $WslDistroName -- grep -P '"(?<=Good signature from \")(.+?)(?=\")"' --max-count 1 -o /tmp/hadoop_sign_cleartext) + '"'
'Please, verify the downloaded Hadoop distribution:' | Write-Output
"`tSHA512 check sum:`n`t`t$hadoopDistroSha512CheckResultTxt" | Write-Output
"`tSignature cleartext:`n$($hadoopDistroSignatureCleartext | foreach {return "`t`t" + $_ + "`n"})" | Write-Output
if (-not $Batch)
{
    if ('y' -eq $(Read-Host -Prompt "Would you like to google for the signer[y/n]?")[0].ToString().ToLower())
    {
        Write-Debug 'assumed "yes"'
        Start-Process $hadoopDistroSignerGoogleQuery.Replace(' ', '%20')
    }
    else
    {
        Write-Debug 'assumed "no"'
    }
    if ('y' -ne $(Read-Host -Prompt "Do you trust the signer[y/n]?")[0].ToString().ToLower())
    {
        Write-Debug 'assumed "no"'
        Write-Host 'Stopped the script.'
        break
    }
}
wsl -d $WslDistroName -- cd / "&&" tar -xzf /tmp/hadoop-3.3.2.tar.gz --overwrite
if ($(wsl -d $WslDistroName -- grep "'export JAVA_HOME=/usr/'" /hadoop-3.3.2/etc/hadoop/hadoop-env.sh -c) -le 0)
{
    wsl -d $WslDistroName -- echo "'export JAVA_HOME=/usr/'" '>>' /hadoop-3.3.2/etc/hadoop/hadoop-env.sh
    '"/hadoop-3.3.2/etc/hadoop/hadoop-env.sh" changed' | Write-Debug
}
if ($(wsl -d $WslDistroName -- grep "'PATH=`$PATH:/hadoop-3.3.2/bin'" ~/.bashrc -c) -le 0)
{
    wsl -d $WslDistroName -- echo "'PATH=`$PATH:/hadoop-3.3.2/bin'" ">>" ~/.bashrc
    '"~/.bashrc" changed"' | Write-Debug
}

removeHadoopTmpFiles($WslDistroName)

##################################################################################################################