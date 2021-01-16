# AzWebappSecutiry Module

[![Build Status](https://dev.azure.com/joao-rosa/AzWebappSecurity/_apis/build/status/JoeBigToe.AzWebappSecurity?branchName=master)](https://dev.azure.com/joao-rosa/AzWebappSecurity/_build/latest?definitionId=1&branchName=master)

This powershell module let's you protect you azure webapp api's behind a WAF policy attached to a frontdoor instance

## TODO
- Sample Build Workflow:
    - [x] .init.ps1  -> Bootstrap by installing InvokeBuild from gallery
    - [x] Clean the BuildOutput folder

---------------
- Build Tasks
    - [ ] Create most-generic and re-usable tasks in \.build\ folder
    - [ ] push those tasks upstream in their associate repos (i.e. PSDepend, PSDeploy)
    - [ ] make those tasks discoverable (i.e. Extension metadata, similar to Plaster Templates)
    - [ ] Evaluate work for discoverability (autoloading?) into InvokeBuild

- Tests
    - [ ] Create Test function to run tests based on folder, so that tasks don't duplicate code (Unit,Integration,QA)

- Build
    - [ ] Extend the project to DSC Builds
    - [ ] Add DSL for Build file / Task Composition as per Brandon Padgett's suggestion
    - [ ] Find what would be needed to build on Linux/PSCore


## Usage (intented)
