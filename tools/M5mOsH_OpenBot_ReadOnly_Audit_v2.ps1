#requires -Version 5.1
<#
M5mOsH OpenBot Read-Only Audit v2.1
Purpose:
- Inspect an existing local Git working tree.
- Report repository identity, branch, latest local commit, worktree status, and remote names.
Safety:
- Does not fetch, pull, push, checkout, reset, clean, stash, or change Git configuration.
- Does not print remote URLs or environment variable values.
- Does not create or modify report files.
- Git optional locks are disabled for this process and the prior environment value is restored.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Host "`n--- $Title ---" -ForegroundColor Cyan
}

function Invoke-GitReadOnly {
    param(
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [switch]$AllowNonZeroExit
    )

    $output = @(& $script:GitExecutable --no-optional-locks --no-pager -C $script:Repo @ArgumentList 2>$null)
    $exitCode = $LASTEXITCODE
    $lines = @($output | ForEach-Object { [string]$_ })

    if ($exitCode -ne 0 -and -not $AllowNonZeroExit) {
        throw "Git inspection failed. Command: git $($ArgumentList -join ' '); exit code: $exitCode."
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Lines = $lines
    }
}

Write-Host 'M5mOsH OpenBot - Read-Only Audit v2.1' -ForegroundColor Green
Write-Host 'Local inspection only. No repository files or report files will be changed.'

$RepoInput = Read-Host 'Enter the path to the existing local OpenBot repository'
if ([string]::IsNullOrWhiteSpace($RepoInput)) {
    throw 'No repository path was provided.'
}

$Repo = $RepoInput.Trim()
if ($Repo.Length -ge 2) {
    $first = $Repo.Substring(0, 1)
    $last = $Repo.Substring($Repo.Length - 1, 1)
    if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
        $Repo = $Repo.Substring(1, $Repo.Length - 2)
    }
}

if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
    throw 'The path does not exist or is not a directory.'
}

$resolvedRepo = Resolve-Path -LiteralPath $Repo
$Repo = $resolvedRepo.ProviderPath
if ([string]::IsNullOrWhiteSpace($Repo)) {
    throw 'The repository path could not be resolved.'
}

$gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $gitCommand) {
    throw 'Git was not found in PATH.'
}
$GitExecutable = $gitCommand.Source

$oldOptionalLocksExists = Test-Path -LiteralPath 'Env:GIT_OPTIONAL_LOCKS'
$oldOptionalLocks = $null
if ($oldOptionalLocksExists) {
    $oldOptionalLocks = (Get-Item -LiteralPath 'Env:GIT_OPTIONAL_LOCKS').Value
}

try {
    $env:GIT_OPTIONAL_LOCKS = '0'

    Write-Section 'Repository validation'
    $probe = Invoke-GitReadOnly -ArgumentList @('rev-parse', '--is-inside-work-tree') -AllowNonZeroExit
    if ($probe.ExitCode -ne 0 -or (($probe.Lines -join '').Trim() -ne 'true')) {
        throw 'The selected directory is not a valid local Git working tree.'
    }
    Write-Host 'Valid local Git working tree.' -ForegroundColor Green

    Write-Section 'Git version'
    $version = @(& $GitExecutable --version 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'Git version could not be read.'
    }
    $version | ForEach-Object { Write-Host $_ }

    Write-Section 'Repository root'
    (Invoke-GitReadOnly -ArgumentList @('rev-parse', '--show-toplevel')).Lines |
        ForEach-Object { Write-Host $_ }

    Write-Section 'Current branch'
    $branchResult = Invoke-GitReadOnly -ArgumentList @('branch', '--show-current')
    $branch = ($branchResult.Lines -join '').Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        Write-Host 'No branch name is available. HEAD may be detached or the repository may have no commit.'
    } else {
        Write-Host $branch
    }

    Write-Section 'Latest local commit'
    $headCheck = Invoke-GitReadOnly -ArgumentList @('rev-parse', '--verify', 'HEAD') -AllowNonZeroExit
    if ($headCheck.ExitCode -eq 0) {
        $latest = Invoke-GitReadOnly -ArgumentList @('log', '-1', '--format=%H%n%cI%n%s')
        $labels = @('Commit SHA', 'Commit date', 'Commit subject')
        for ($i = 0; $i -lt $latest.Lines.Count; $i++) {
            if ($i -lt $labels.Count) {
                Write-Host ("{0}: {1}" -f $labels[$i], $latest.Lines[$i])
            } else {
                Write-Host $latest.Lines[$i]
            }
        }
    } else {
        Write-Host 'No local HEAD commit is available.'
    }

    Write-Section 'Working tree status'
    $status = Invoke-GitReadOnly -ArgumentList @('status', '--short', '--branch', '--untracked-files=normal')
    if ($status.Lines.Count -eq 0) {
        Write-Host '(Git returned no status details.)'
    } else {
        $status.Lines | ForEach-Object { Write-Host $_ }
    }

    Write-Section 'Remote names only'
    $remotes = Invoke-GitReadOnly -ArgumentList @('remote')
    if ($remotes.Lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace(($remotes.Lines -join '').Trim())) {
        Write-Host 'No remotes are configured.'
    } else {
        $remotes.Lines | ForEach-Object { Write-Host $_ }
    }

    Write-Section 'Audit limits'
    Write-Host 'No fetch, pull, push, checkout, reset, clean, stash, or configuration change was performed.'
    Write-Host 'Remote URLs and environment variable values were not printed.'
    Write-Host 'No report file was created.'
}
finally {
    if ($oldOptionalLocksExists) {
        $env:GIT_OPTIONAL_LOCKS = $oldOptionalLocks
    } else {
        Remove-Item -LiteralPath 'Env:GIT_OPTIONAL_LOCKS' -ErrorAction SilentlyContinue
    }
}
