#Requires -Modules psake

###############################################################################
# Dot source the user's customized properties and extension tasks.
###############################################################################
. $PSScriptRoot\build.settings.ps1

###############################################################################
# Core task implementations. Avoid modifying these tasks.
###############################################################################
Task default -depends Build

Task Build {
    Write-Host "Success!"
}