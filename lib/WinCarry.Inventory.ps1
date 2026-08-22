function Invoke-ExternalCommandCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [string[]]$Arguments = @()
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return [ordered]@{
            available = $false
            command = $CommandName
            arguments = @($Arguments)
            source = ""
            exitCode = $null
            lines = @()
            error = "Command not found."
        }
    }

    try {
        $output = & $command.Source @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $lines = @($output | ForEach-Object { [string]$_ })

        return [ordered]@{
            available = $true
            command = $CommandName
            arguments = @($Arguments)
            source = $command.Source
            exitCode = $exitCode
            lines = $lines
            error = ""
        }
    } catch {
        return [ordered]@{
            available = $true
            command = $CommandName
            arguments = @($Arguments)
            source = $command.Source
            exitCode = $LASTEXITCODE
            lines = @()
            error = $_.Exception.Message
        }
    }
}

function Convert-FixedWidthTable {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @(),

        [Parameter(Mandatory = $true)]
        [string[]]$ColumnNames,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredColumnNames
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    $headerIndex = -1
    $header = ""

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $candidate = $Lines[$index]
        $hasRequiredColumns = $true

        foreach ($requiredColumn in $RequiredColumnNames) {
            if ($candidate.IndexOf($requiredColumn, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $hasRequiredColumns = $false
                break
            }
        }

        if ($hasRequiredColumns) {
            $headerIndex = $index
            $header = $candidate
            break
        }
    }

    if ($headerIndex -lt 0) {
        return @()
    }

    $columns = @()
    foreach ($columnName in $ColumnNames) {
        $start = $header.IndexOf($columnName, [StringComparison]::OrdinalIgnoreCase)
        if ($start -ge 0) {
            $columns += [pscustomobject]@{
                name = $columnName
                start = [int]$start
                end = $null
            }
        }
    }

    $columns = @($columns | Sort-Object -Property @{ Expression = { [int]$_.start } }, @{ Expression = { [string]$_.name } })
    for ($index = 0; $index -lt $columns.Count; $index++) {
        $columns[$index].end = $null
        for ($nextIndex = $index + 1; $nextIndex -lt $columns.Count; $nextIndex++) {
            if ([int]$columns[$nextIndex].start -gt [int]$columns[$index].start) {
                $columns[$index].end = [int]$columns[$nextIndex].start
                break
            }
        }
    }

    $rows = @()
    for ($index = $headerIndex + 1; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed -match "^[-\s]+$") {
            continue
        }
        if ($trimmed -match "^\S+\s+\d+%$") {
            continue
        }
        if ($trimmed -match "No installed package") {
            continue
        }

        $row = [ordered]@{}
        foreach ($column in $columns) {
            $columnStart = [int]$column.start
            $columnEnd = $column.end

            if ($columnStart -lt 0 -or $line.Length -le $columnStart) {
                $value = ""
            } else {
                if ($null -ne $columnEnd -and [int]$columnEnd -gt $columnStart) {
                    $safeEnd = [Math]::Min([int]$columnEnd, [int]$line.Length)
                    $length = $safeEnd - $columnStart
                } else {
                    $length = 0
                }

                if ($length -gt 0) {
                    $value = $line.Substring($columnStart, $length).Trim()
                } else {
                    $value = $line.Substring($columnStart).Trim()
                }
            }

            $row[$column.name] = $value
        }

        $hasRequiredValues = $true
        foreach ($requiredColumn in $RequiredColumnNames) {
            if (-not $row.Contains($requiredColumn) -or [string]::IsNullOrWhiteSpace($row[$requiredColumn])) {
                $hasRequiredValues = $false
                break
            }
        }

        if ($hasRequiredValues) {
            $rows += $row
        }
    }

    return $rows
}

function Convert-WingetListFallbackTable {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @()
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    $rows = @()
    $seenSeparator = $false

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed -match "^[-\s]+$") {
            $seenSeparator = $true
            continue
        }
        if ($trimmed -match "^\S+\s+\d+%$") {
            continue
        }
        if ($trimmed -match "No installed package") {
            continue
        }

        $parts = @($trimmed -split "\s{2,}" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -lt 2) {
            continue
        }

        if ($parts[1] -ieq "Id") {
            continue
        }
        if ((-not $seenSeparator) -and ($parts[0] -match "^(Name|Nama)$")) {
            continue
        }

        $name = $parts[0].Trim()
        $packageId = $parts[1].Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }

        $version = ""
        $available = ""
        $source = ""

        if ($parts.Count -ge 3) {
            $version = $parts[2].Trim()
        }
        if ($parts.Count -eq 4) {
            if ($parts[3] -match "^(winget|msstore)$") {
                $source = $parts[3].Trim()
            } else {
                $available = $parts[3].Trim()
            }
        }
        if ($parts.Count -ge 5) {
            $available = $parts[3].Trim()
            $source = $parts[4].Trim()
        }

        $rows += [ordered]@{
            Name = $name
            Id = $packageId
            Version = $version
            Available = $available
            Source = $source
        }
    }

    return $rows
}

function Get-CommandOutputSample {
    param(
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines = @(),

        [int]$Limit = 5
    )

    $sample = @()
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed.Length -gt 160) {
            $trimmed = $trimmed.Substring(0, 160) + "..."
        }

        $sample += $trimmed
        if ($sample.Count -ge $Limit) {
            break
        }
    }

    return $sample
}

function Convert-WingetCaptureToRows {
    param(
        [Parameter(Mandatory = $true)]
        $Capture
    )

    $warnings = @()
    $argumentText = (($Capture.arguments | ForEach-Object { [string]$_ }) -join " ").Trim()
    if ([string]::IsNullOrWhiteSpace($argumentText)) {
        $argumentText = "<none>"
    }

    if (-not [string]::IsNullOrWhiteSpace($Capture.error)) {
        $warnings += ("winget {0} failed: {1}" -f $argumentText, $Capture.error)
    }

    if (($null -ne $Capture.exitCode) -and ($Capture.exitCode -ne 0)) {
        $warnings += ("winget {0} exited with code {1}." -f $argumentText, $Capture.exitCode)
    }

    $rows = @(Convert-FixedWidthTable -Lines $Capture.lines -ColumnNames @("Name", "Id", "Version", "Available", "Source") -RequiredColumnNames @("Name", "Id"))
    $parser = "fixed-width"
    if ($rows.Count -eq 0) {
        $rows = @(Convert-WingetListFallbackTable -Lines $Capture.lines)
        $parser = "whitespace-fallback"
    }

    return [ordered]@{
        rows = $rows
        parser = $parser
        warnings = $warnings
        outputSample = @(Get-CommandOutputSample -Lines $Capture.lines)
        argumentText = $argumentText
    }
}

function New-ScanEvidenceRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$EvidenceType,

        [Parameter(Mandatory = $true)]
        $Data
    )

    return [ordered]@{
        source = $Source
        evidenceType = $EvidenceType
        detectedAt = (Get-Date).ToString("o")
        data = $Data
    }
}

function Get-MapValue {
    param(
        $Map,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -eq $Map) {
        return ""
    }

    if ($Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Key)) {
            return $Map[$Key]
        }

        return ""
    }

    $property = $Map.PSObject.Properties[$Key]
    if ($null -ne $property) {
        return $property.Value
    }

    return ""
}

function Add-UniqueValue {
    param(
        [object[]]$Values,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @($Values)
    }

    $existing = @($Values | Where-Object { $_ -eq $Value })
    if ($existing.Count -gt 0) {
        return @($Values)
    }

    return @($Values + $Value)
}

function Normalize-Whitespace {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    return (($Text.Trim() -replace "\s+", " "))
}

function Get-NormalizedName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    $normalized = $Name.ToLowerInvariant()
    $normalized = $normalized -replace "\(.*?\)", " "
    $normalized = $normalized -replace "\b(x64|x86|64-bit|32-bit|user|machine|en-us|id-id)\b", " "
    $normalized = $normalized -replace "[^a-z0-9]+", " "
    return (Normalize-Whitespace -Text $normalized)
}

function Get-NameTokens {
    param([string]$Name)

    $normalized = Get-NormalizedName -Name $Name
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return @()
    }

    $stopWords = @("the", "inc", "llc", "ltd", "corp", "corporation", "company", "co", "microsoft")
    return @($normalized.Split(" ") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $stopWords -notcontains $_ })
}

function Test-StrongNameMatch {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftNormalized = Get-NormalizedName -Name $Left
    $rightNormalized = Get-NormalizedName -Name $Right
    if ([string]::IsNullOrWhiteSpace($leftNormalized) -or [string]::IsNullOrWhiteSpace($rightNormalized)) {
        return $false
    }

    if ($leftNormalized -eq $rightNormalized) {
        return $true
    }

    $leftTokens = @(Get-NameTokens -Name $Left)
    $rightTokens = @(Get-NameTokens -Name $Right)
    if ($leftTokens.Count -eq 0 -or $rightTokens.Count -eq 0) {
        return $false
    }

    if ($leftTokens.Count -eq 1 -and $rightTokens.Count -eq 1) {
        return ($leftTokens[0] -eq $rightTokens[0])
    }

    $smaller = $leftTokens
    $larger = $rightTokens
    if ($rightTokens.Count -lt $leftTokens.Count) {
        $smaller = $rightTokens
        $larger = $leftTokens
    }

    if ($smaller.Count -lt 2) {
        return $false
    }

    foreach ($token in $smaller) {
        if ($larger -notcontains $token) {
            return $false
        }
    }

    return $true
}

function Get-NormalizedPublisher {
    param([string]$Publisher)

    $normalized = Get-NormalizedName -Name $Publisher
    $normalized = $normalized -replace "\b(inc|llc|ltd|corp|corporation|company|co)\b", " "
    return (Normalize-Whitespace -Text $normalized)
}

function Get-NormalizedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    $normalized = $expanded.Replace("/", "\").TrimEnd("\")
    return $normalized.ToLowerInvariant()
}

function Get-ExecutableNameFromPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        return ([System.IO.Path]::GetFileNameWithoutExtension($Path)).ToLowerInvariant()
    } catch {
        return ""
    }
}

function Test-PathRelationship {
    param(
        [string]$LeftPath,
        [string]$RightPath
    )

    $left = Get-NormalizedPath -Path $LeftPath
    $right = Get-NormalizedPath -Path $RightPath
    if ([string]::IsNullOrWhiteSpace($left) -or [string]::IsNullOrWhiteSpace($right)) {
        return $false
    }

    if ($left -eq $right) {
        return $true
    }

    return ($left.StartsWith($right + "\") -or $right.StartsWith($left + "\"))
}

function Get-NormalizedPackageId {
    param([string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) {
        return ""
    }

    return (($PackageId.Trim()).ToLowerInvariant())
}

function Get-ShortHash {
    param([string]$Text)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hashBytes = $sha1.ComputeHash($bytes)
        $hash = (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "")
        return $hash.Substring(0, 8)
    } finally {
        $sha1.Dispose()
    }
}

function New-StableAppId {
    param(
        [string]$Name,
        [string]$Publisher,
        [string]$PackageId,
        [string]$RegistryPath
    )

    $basis = ("{0}|{1}|{2}|{3}" -f $Name, $Publisher, $PackageId, $RegistryPath)
    $slug = (Get-NormalizedName -Name $Name) -replace "\s+", "-"
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = "unknown-app"
    }
    if ($slug.Length -gt 48) {
        $slug = $slug.Substring(0, 48).TrimEnd("-")
    }

    return ("app-{0}-{1}" -f $slug, (Get-ShortHash -Text $basis))
}

function Convert-EvidenceToAppCandidate {
    param(
        [Parameter(Mandatory = $true)]
        $Record,

        [Parameter(Mandatory = $true)]
        [int]$EvidenceIndex
    )

    $data = $Record.data
    $candidate = [ordered]@{
        source = [string]$Record.source
        evidenceType = [string]$Record.evidenceType
        evidenceIndex = $EvidenceIndex
        name = ""
        publisher = ""
        version = ""
        installLocation = ""
        executablePath = ""
        workingDirectory = ""
        packageManager = ""
        packageId = ""
        packageSource = ""
        registryPath = ""
        systemComponent = ""
        parentLabel = ""
        normalizedName = ""
        normalizedPublisher = ""
        normalizedInstallLocation = ""
        normalizedExecutablePath = ""
        normalizedPackageId = ""
        executableName = ""
    }

    switch ([string]$Record.source) {
        "registry" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "displayName")
            $candidate.publisher = [string](Get-MapValue -Map $data -Key "publisher")
            $candidate.version = [string](Get-MapValue -Map $data -Key "displayVersion")
            $candidate.installLocation = [string](Get-MapValue -Map $data -Key "installLocation")
            $candidate.registryPath = [string](Get-MapValue -Map $data -Key "registryPath")
            $candidate.systemComponent = [string](Get-MapValue -Map $data -Key "systemComponent")
        }
        "winget" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.version = [string](Get-MapValue -Map $data -Key "version")
            $candidate.packageManager = "winget"
            $candidate.packageId = [string](Get-MapValue -Map $data -Key "packageId")
            $candidate.packageSource = [string](Get-MapValue -Map $data -Key "source")
        }
        "chocolatey" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "packageName")
            $candidate.version = [string](Get-MapValue -Map $data -Key "version")
            $candidate.packageManager = "chocolatey"
            $candidate.packageId = [string](Get-MapValue -Map $data -Key "packageName")
        }
        "scoop" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.version = [string](Get-MapValue -Map $data -Key "version")
            $candidate.packageManager = "scoop"
            $candidate.packageId = [string](Get-MapValue -Map $data -Key "name")
            $candidate.packageSource = [string](Get-MapValue -Map $data -Key "bucket")
        }
        "startMenu" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.executablePath = [string](Get-MapValue -Map $data -Key "targetPath")
            $candidate.workingDirectory = [string](Get-MapValue -Map $data -Key "workingDirectory")
        }
        "knownFolder" {
            $candidate.name = [string](Get-MapValue -Map $data -Key "name")
            $candidate.installLocation = [string](Get-MapValue -Map $data -Key "path")
            $candidate.parentLabel = [string](Get-MapValue -Map $data -Key "parentLabel")
        }
    }

    $candidate.normalizedName = Get-NormalizedName -Name $candidate.name
    $candidate.normalizedPublisher = Get-NormalizedPublisher -Publisher $candidate.publisher
    $candidate.normalizedInstallLocation = Get-NormalizedPath -Path $candidate.installLocation
    $candidate.normalizedExecutablePath = Get-NormalizedPath -Path $candidate.executablePath
    $candidate.normalizedPackageId = Get-NormalizedPackageId -PackageId $candidate.packageId
    $candidate.executableName = Get-ExecutableNameFromPath -Path $candidate.executablePath

    if ([string]::IsNullOrWhiteSpace($candidate.name)) {
        return $null
    }

    return $candidate
}

function New-LogicalAppFromCandidate {
    param(
        [Parameter(Mandatory = $true)]
        $Candidate
    )

    $id = New-StableAppId -Name $Candidate.name -Publisher $Candidate.publisher -PackageId $Candidate.packageId -RegistryPath $Candidate.registryPath
    return [ordered]@{
        id = $id
        name = [string]$Candidate.name
        publisher = [string]$Candidate.publisher
        versionDetected = [string]$Candidate.version
        installLocation = [string]$Candidate.installLocation
        executablePath = [string]$Candidate.executablePath
        sources = @()
        package = $null
        packages = @()
        classification = "Unknown"
        restoreConfidence = "Unknown"
        restoreStrategy = "manual-review"
        reasons = @()
        warnings = @()
        evidence = @()
        evidenceCount = 0
        identity = [ordered]@{
            normalizedName = [string]$Candidate.normalizedName
            normalizedPublisher = [string]$Candidate.normalizedPublisher
            normalizedInstallLocation = [string]$Candidate.normalizedInstallLocation
            normalizedExecutablePath = [string]$Candidate.normalizedExecutablePath
            executableName = [string]$Candidate.executableName
            registryPath = [string]$Candidate.registryPath
            systemComponent = [string]$Candidate.systemComponent
            folderParent = [string]$Candidate.parentLabel
        }
    }
}

function Add-CandidateToLogicalApp {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        $Candidate
    )

    $App.sources = Add-UniqueValue -Values $App.sources -Value $Candidate.source
    $App.evidence += [ordered]@{
        index = $Candidate.evidenceIndex
        source = [string]$Candidate.source
        evidenceType = [string]$Candidate.evidenceType
        name = [string]$Candidate.name
        publisher = [string]$Candidate.publisher
        version = [string]$Candidate.version
        installLocation = [string]$Candidate.installLocation
        executablePath = [string]$Candidate.executablePath
        packageManager = [string]$Candidate.packageManager
        packageId = [string]$Candidate.packageId
        systemComponent = [string]$Candidate.systemComponent
    }
    $App.evidenceCount = $App.evidence.Count

    if ([string]::IsNullOrWhiteSpace($App.publisher) -and -not [string]::IsNullOrWhiteSpace($Candidate.publisher)) {
        $App.publisher = [string]$Candidate.publisher
        $App.identity.normalizedPublisher = [string]$Candidate.normalizedPublisher
    }
    if ([string]::IsNullOrWhiteSpace($App.versionDetected) -and -not [string]::IsNullOrWhiteSpace($Candidate.version)) {
        $App.versionDetected = [string]$Candidate.version
    }
    if ([string]::IsNullOrWhiteSpace($App.installLocation) -and -not [string]::IsNullOrWhiteSpace($Candidate.installLocation)) {
        $App.installLocation = [string]$Candidate.installLocation
        $App.identity.normalizedInstallLocation = [string]$Candidate.normalizedInstallLocation
    }
    if ([string]::IsNullOrWhiteSpace($App.executablePath) -and -not [string]::IsNullOrWhiteSpace($Candidate.executablePath)) {
        $App.executablePath = [string]$Candidate.executablePath
        $App.identity.normalizedExecutablePath = [string]$Candidate.normalizedExecutablePath
        $App.identity.executableName = [string]$Candidate.executableName
    }
    if ([string]::IsNullOrWhiteSpace($App.identity.registryPath) -and -not [string]::IsNullOrWhiteSpace($Candidate.registryPath)) {
        $App.identity.registryPath = [string]$Candidate.registryPath
    }
    if ([string]::IsNullOrWhiteSpace($App.identity.systemComponent) -and -not [string]::IsNullOrWhiteSpace($Candidate.systemComponent)) {
        $App.identity.systemComponent = [string]$Candidate.systemComponent
    }
    if ([string]::IsNullOrWhiteSpace($App.identity.folderParent) -and -not [string]::IsNullOrWhiteSpace($Candidate.parentLabel)) {
        $App.identity.folderParent = [string]$Candidate.parentLabel
    }

    if (-not [string]::IsNullOrWhiteSpace($Candidate.packageManager) -and -not [string]::IsNullOrWhiteSpace($Candidate.packageId)) {
        $packageExists = $false
        foreach ($package in @($App.packages)) {
            if ($package.manager -eq $Candidate.packageManager -and $package.id -eq $Candidate.packageId) {
                $packageExists = $true
                break
            }
        }

        if (-not $packageExists) {
            $App.packages += [ordered]@{
                manager = [string]$Candidate.packageManager
                id = [string]$Candidate.packageId
                version = [string]$Candidate.version
                source = [string]$Candidate.packageSource
            }
        }
    }
}

function Find-LogicalAppMatch {
    param(
        [object[]]$Apps,
        [Parameter(Mandatory = $true)]
        $Candidate
    )

    $bestApp = $null
    $bestScore = 0

    foreach ($app in $Apps) {
        $score = 0

        if (-not [string]::IsNullOrWhiteSpace($Candidate.normalizedPackageId)) {
            foreach ($package in @($app.packages)) {
                if ($package.manager -eq $Candidate.packageManager -and (Get-NormalizedPackageId -PackageId $package.id) -eq $Candidate.normalizedPackageId) {
                    $score = [Math]::Max($score, 100)
                }
            }
        }

        if (Test-PathRelationship -LeftPath $Candidate.installLocation -RightPath $app.installLocation) {
            $score = [Math]::Max($score, 90)
        }
        if (Test-PathRelationship -LeftPath $Candidate.executablePath -RightPath $app.installLocation) {
            $score = [Math]::Max($score, 90)
        }

        if (Test-StrongNameMatch -Left $Candidate.name -Right $app.name) {
            $nameScore = 60
            if (-not [string]::IsNullOrWhiteSpace($Candidate.normalizedPublisher) -and $Candidate.normalizedPublisher -eq $app.identity.normalizedPublisher) {
                $nameScore += 20
            }
            if (-not [string]::IsNullOrWhiteSpace($Candidate.packageManager) -or @($app.packages).Count -gt 0) {
                $nameScore += 10
            }
            if ($Candidate.source -eq "knownFolder") {
                $nameScore -= 20
            }

            $score = [Math]::Max($score, $nameScore)
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestApp = $app
        }
    }

    if ($bestScore -ge 60) {
        return $bestApp
    }

    return $null
}

function Test-AppTextMatch {
    param(
        [Parameter(Mandatory = $true)]
        $App,
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $text = ((@($App.name, $App.publisher, $App.installLocation, $App.executablePath, (@($App.packages) | ForEach-Object { $_.id })) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " ").ToLowerInvariant()
    return ($text -match $Pattern)
}

function Test-AppEvidenceTextMatch {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [string[]]$Fields = @("name", "publisher", "packageId")
    )

    foreach ($evidence in @($App.evidence)) {
        $parts = @()
        foreach ($field in $Fields) {
            $value = [string](Get-MapValue -Map $evidence -Key $field)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $parts += $value
            }
        }

        if ($parts.Count -eq 0) {
            continue
        }

        $text = ($parts -join " ").ToLowerInvariant()
        if ($text -match $Pattern) {
            return $true
        }
    }

    return $false
}

function Set-LogicalAppClassification {
    param(
        [Parameter(Mandatory = $true)]
        $App
    )

    $classification = "Unknown"
    $confidence = "Unknown"
    $strategy = "manual-review"
    $reasons = @()
    $warnings = @()

    $sources = @($App.sources)
    $packages = @($App.packages)
    $hasWinget = (@($packages | Where-Object { $_.manager -eq "winget" }).Count -gt 0)
    $hasChocolatey = (@($packages | Where-Object { $_.manager -eq "chocolatey" }).Count -gt 0)
    $hasScoop = (@($packages | Where-Object { $_.manager -eq "scoop" }).Count -gt 0)
    $isKnownFolderOnly = ($sources.Count -eq 1 -and $sources[0] -eq "knownFolder")
    $hasSystemComponentEvidence = (@($App.evidence | Where-Object { [string](Get-MapValue -Map $_ -Key "systemComponent") -eq "1" }).Count -gt 0)

    $runtimePattern = "(visual c\+\+.*(redistribut|runtime|runt|minimum|additional|debug|uwp)|\.net.*(runtime|sdk|desktop runtime)|webview2 runtime|directx|windows sdk)"
    $driverPattern = "\b(driver|virtual display|virtual usb|chipset|firmware|printer driver|scanner driver|bluetooth driver|audio driver|display driver)\b"
    $securityPattern = "\b(antivirus|endpoint|edr|firewall|[a-z0-9]*vpn[a-z0-9]*|wireguard|security agent)\b"

    if (Test-AppEvidenceTextMatch -App $App -Pattern $runtimePattern -Fields @("name", "publisher", "packageId")) {
        $classification = "Unsupported / risky"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Runtime or SDK dependency should be installed by Windows, apps, or package managers as needed."
    } elseif (Test-AppEvidenceTextMatch -App $App -Pattern $driverPattern -Fields @("name", "publisher", "packageId")) {
        $classification = "Driver / system component"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Name or metadata indicates driver/device-level software."
    } elseif (Test-AppEvidenceTextMatch -App $App -Pattern $securityPattern -Fields @("name", "publisher", "packageId")) {
        $classification = "Unsupported / risky"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Security or network software may include services, drivers, certificates, or policy state."
    } elseif (Test-AppTextMatch -App $App -Pattern "\b(windowsapps|msstore)\b") {
        $classification = "Microsoft Store / UWP"
        $confidence = "Unsupported"
        $strategy = "manual-review"
        $reasons += "Microsoft Store/UWP app restore is outside the MVP automatic restore scope."
    } elseif (Test-AppTextMatch -App $App -Pattern "\b(docker desktop|postgresql|mysql|mariadb|sql server|mongodb|redis|vmware|virtualbox|hyper-v|wsl)\b") {
        $classification = "Service-heavy"
        $confidence = "Low"
        $strategy = "manual-review"
        $reasons += "App likely depends on services, data directories, networking, drivers, or local machine state."
    } elseif ($hasScoop) {
        $classification = "Scoop-managed"
        $confidence = "High"
        $strategy = "restore-via-scoop"
        $reasons += "Found Scoop package metadata."
    } elseif ($App.identity.folderParent -match "WinCarry portable|WinCarry manual apps") {
        $classification = "Portable / Self-contained"
        $confidence = "Medium"
        $strategy = "manual-review"
        $reasons += "Found app folder under a WinCarry-managed portable/manual location."
        if ($isKnownFolderOnly) {
            $warnings += "Folder presence alone is supporting evidence; verify the app manually before restore."
        }
    } elseif ($hasWinget) {
        $classification = "Winget reinstallable"
        $confidence = "Medium"
        $strategy = "reinstall-via-package-manager"
        $reasons += "Found winget package metadata."
    } elseif ($hasChocolatey) {
        $classification = "Chocolatey reinstallable"
        $confidence = "Medium"
        $strategy = "reinstall-via-package-manager"
        $reasons += "Found Chocolatey package metadata."
    } elseif ($hasSystemComponentEvidence) {
        $classification = "Unsupported / risky"
        $confidence = "Unsupported"
        $strategy = "do-not-restore"
        $reasons += "Registry marks this entry as a Windows system component."
    } elseif ($sources -contains "registry") {
        $classification = "Installer-based / manual reinstall"
        $confidence = "Low"
        $strategy = "manual-reinstall"
        $reasons += "Found uninstall registry metadata but no package-manager identity."
    } else {
        $classification = "Unknown"
        $confidence = "Unknown"
        $strategy = "manual-review"
        $reasons += "Evidence is not strong enough for an automatic restore strategy."
    }

    if ($packages.Count -gt 0) {
        $packageSummary = (($packages | ForEach-Object { "{0}:{1}" -f $_.manager, $_.id }) -join ", ")
        $reasons += ("Package evidence: {0}." -f $packageSummary)
    }
    if ($sources.Count -gt 0) {
        $reasons += ("Evidence sources: {0}." -f (($sources | Sort-Object) -join ", "))
    }
    if ($hasSystemComponentEvidence -and ($hasWinget -or $hasChocolatey -or $hasScoop)) {
        $warnings += "Registry also marks one entry as a system component; prefer package-manager reinstall and verify manually."
    }

    $App.classification = $classification
    $App.restoreConfidence = $confidence
    $App.restoreStrategy = $strategy
    $App.reasons = @($reasons)
    $App.warnings = @($warnings)

    if ($packages.Count -gt 0) {
        if ($hasScoop) {
            $App.package = @($packages | Where-Object { $_.manager -eq "scoop" } | Select-Object -First 1)[0]
        } elseif ($hasWinget) {
            $App.package = @($packages | Where-Object { $_.manager -eq "winget" } | Select-Object -First 1)[0]
        } elseif ($hasChocolatey) {
            $App.package = @($packages | Where-Object { $_.manager -eq "chocolatey" } | Select-Object -First 1)[0]
        }
    }
}

function New-LogicalAppsFromEvidence {
    param(
        [object[]]$Evidence
    )

    $apps = @()
    for ($index = 0; $index -lt $Evidence.Count; $index++) {
        $candidate = Convert-EvidenceToAppCandidate -Record $Evidence[$index] -EvidenceIndex $index
        if ($null -eq $candidate) {
            continue
        }

        $match = Find-LogicalAppMatch -Apps $apps -Candidate $candidate
        if ($null -eq $match) {
            $match = New-LogicalAppFromCandidate -Candidate $candidate
            $apps += $match
        }

        Add-CandidateToLogicalApp -App $match -Candidate $candidate
    }

    foreach ($app in $apps) {
        Set-LogicalAppClassification -App $app
    }

    return @($apps | Sort-Object -Property @{ Expression = { [string]$_.classification } }, @{ Expression = { [string]$_.name } })
}

function Get-ClassificationSummary {
    param([object[]]$Apps)

    $summary = [ordered]@{}
    foreach ($app in $Apps) {
        $key = [string]$app.classification
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "Unknown"
        }

        if (-not $summary.Contains($key)) {
            $summary[$key] = 0
        }
        $summary[$key] = [int]$summary[$key] + 1
    }

    return $summary
}

function Get-ObjectKeys {
    param($Object)

    if ($null -eq $Object) {
        return @()
    }

    if ($Object -is [System.Collections.IDictionary]) {
        return @($Object.Keys)
    }

    return @($Object.PSObject.Properties.Name)
}

function ConvertTo-ArrayValue {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [System.Collections.IDictionary]) {
        return @($Value)
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }

        return @($Value)
    }

    return @($Value | Where-Object { $null -ne $_ -and -not ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_)) })
}

function Get-AppPackages {
    param($App)

    $packages = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "packages"))
    if (@($packages).Count -gt 0) {
        return @($packages)
    }

    return @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "package"))
}

function Test-AppHasPackageId {
    param($App)

    foreach ($package in (Get-AppPackages -App $App)) {
        $packageId = [string](Get-MapValue -Map $package -Key "id")
        if (-not [string]::IsNullOrWhiteSpace($packageId)) {
            return $true
        }
    }

    return $false
}

function Get-AppPackageSummaryText {
    param($App)

    $parts = @()
    foreach ($package in (Get-AppPackages -App $App)) {
        $manager = [string](Get-MapValue -Map $package -Key "manager")
        $packageId = [string](Get-MapValue -Map $package -Key "id")
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($manager)) {
            $parts += $packageId
        } else {
            $parts += ("{0}:{1}" -f $manager, $packageId)
        }
    }

    if ($parts.Count -eq 0) {
        return "manual"
    }

    return ($parts -join ", ")
}

function Get-AppReasonsText {
    param($App)

    $reasons = ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "reasons")
    if ($reasons.Count -eq 0) {
        return "No reason recorded."
    }

    return (($reasons | ForEach-Object { [string]$_ }) -join " ")
}

function Get-AppWarningsText {
    param($App)

    $warnings = ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "warnings")
    if ($warnings.Count -eq 0) {
        return ""
    }

    return (($warnings | ForEach-Object { [string]$_ }) -join " ")
}

function Get-ConfidenceSummary {
    param([object[]]$Apps)

    $summary = [ordered]@{}
    foreach ($app in $Apps) {
        $key = [string](Get-MapValue -Map $app -Key "restoreConfidence")
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "Unknown"
        }
        if (-not $summary.Contains($key)) {
            $summary[$key] = 0
        }
        $summary[$key] = [int]$summary[$key] + 1
    }

    return $summary
}

function Get-ManualReinstallApps {
    param([object[]]$Apps)

    $manualClassifications = @(
        "Installer-based / manual reinstall",
        "Unknown",
        "Portable / Self-contained",
        "Service-heavy"
    )

    return @($Apps | Where-Object {
        $confidence = [string](Get-MapValue -Map $_ -Key "restoreConfidence")
        $classification = [string](Get-MapValue -Map $_ -Key "classification")
        $strategy = [string](Get-MapValue -Map $_ -Key "restoreStrategy")
        $hasPackage = Test-AppHasPackageId -App $_

        ($confidence -ne "Unsupported") -and (
            (-not $hasPackage) -or
            ($strategy -eq "manual-reinstall") -or
            ($manualClassifications -contains $classification)
        )
    })
}

function Get-UnsupportedApps {
    param([object[]]$Apps)

    return @($Apps | Where-Object {
        $confidence = [string](Get-MapValue -Map $_ -Key "restoreConfidence")
        $classification = [string](Get-MapValue -Map $_ -Key "classification")
        ($confidence -eq "Unsupported") -or ($classification -eq "Unsupported / risky") -or ($classification -eq "Driver / system component") -or ($classification -eq "Microsoft Store / UWP")
    })
}

function New-AppSummaryRecord {
    param($App)

    return [ordered]@{
        id = [string](Get-MapValue -Map $App -Key "id")
        name = [string](Get-MapValue -Map $App -Key "name")
        classification = [string](Get-MapValue -Map $App -Key "classification")
        restoreConfidence = [string](Get-MapValue -Map $App -Key "restoreConfidence")
        restoreStrategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
        package = (Get-AppPackageSummaryText -App $App)
        reasons = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "reasons"))
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "warnings"))
    }
}

function Convert-PackageManagerStatusToMap {
    param(
        [object[]]$PackageManagers,
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $map = [ordered]@{}
    foreach ($manager in $PackageManagers) {
        $name = [string](Get-MapValue -Map $manager -Key "name")
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $entry = [ordered]@{
            available = [bool](Get-MapValue -Map $manager -Key "available")
            version = [string](Get-MapValue -Map $manager -Key "version")
            source = [string](Get-MapValue -Map $manager -Key "source")
            offlineSafeSkipped = [bool](Get-MapValue -Map $manager -Key "offlineSafeSkipped")
        }
        if ($name -eq "scoop") {
            $entry["root"] = (Join-Path $RootPath "scoop")
        }

        $map[$name] = $entry
    }

    return $map
}

function Convert-AppForManifest {
    param(
        [Parameter(Mandatory = $true)]
        $App,

        [Parameter(Mandatory = $true)]
        [string]$DetectedAt
    )

    return [ordered]@{
        id = [string](Get-MapValue -Map $App -Key "id")
        name = [string](Get-MapValue -Map $App -Key "name")
        publisher = [string](Get-MapValue -Map $App -Key "publisher")
        versionDetected = [string](Get-MapValue -Map $App -Key "versionDetected")
        installLocation = [string](Get-MapValue -Map $App -Key "installLocation")
        executablePath = [string](Get-MapValue -Map $App -Key "executablePath")
        source = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "sources"))
        package = (Get-MapValue -Map $App -Key "package")
        packages = @(Get-AppPackages -App $App)
        classification = [string](Get-MapValue -Map $App -Key "classification")
        restoreConfidence = [string](Get-MapValue -Map $App -Key "restoreConfidence")
        restoreStrategy = [string](Get-MapValue -Map $App -Key "restoreStrategy")
        reasons = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "reasons"))
        warnings = @(ConvertTo-ArrayValue -Value (Get-MapValue -Map $App -Key "warnings"))
        configPaths = @()
        detectedAt = $DetectedAt
    }
}

function New-AppManifestFromScan {
    param(
        [Parameter(Mandatory = $true)]
        $Scan,

        [switch]$OfflineSafe
    )

    $rootPath = [string]$Scan.root.resolvedRoot
    $os = Get-OperatingSystemInfo
    $user = Get-CurrentUserInfo
    $admin = Get-AdminStatus
    $effectiveOfflineSafe = ([bool]$OfflineSafe -or [bool](Get-MapValue -Map $Scan -Key "offlineSafeMode"))
    $packageManagers = @(Get-PackageManagerStatus -OfflineSafe:$effectiveOfflineSafe)
    $apps = @($Scan.apps | ForEach-Object { Convert-AppForManifest -App $_ -DetectedAt $Scan.createdAt })
    $manualApps = @(Get-ManualReinstallApps -Apps $apps | ForEach-Object { New-AppSummaryRecord -App $_ })
    $unsupportedApps = @(Get-UnsupportedApps -Apps $apps | ForEach-Object { New-AppSummaryRecord -App $_ })

    $manifest = [ordered]@{
        schemaVersion = "1.0"
        createdAt = (Get-Date).ToString("o")
        toolName = $script:ToolName
        offlineSafeMode = [bool]$effectiveOfflineSafe
        sourceScan = [ordered]@{
            schemaVersion = [string]$Scan.schemaVersion
            createdAt = [string]$Scan.createdAt
            offlineSafeMode = [bool](Get-MapValue -Map $Scan -Key "offlineSafeMode")
            evidenceCount = @($Scan.evidence).Count
            sourceCounts = $Scan.sources
            warnings = @($Scan.warnings)
        }
        machine = [ordered]@{
            computerName = [string]$user.machineName
            windowsVersion = ("{0} {1}" -f $os.caption, $os.architecture)
            osCaption = [string]$os.caption
            osVersion = [string]$os.version
            architecture = [string]$os.architecture
            userName = [string]$user.userName
            userDomain = [string]$user.domainName
            userProfile = [string]$user.userProfile
            isAdmin = [bool]$admin.isAdmin
        }
        root = [ordered]@{
            winCarryRoot = $rootPath
        }
        packageManagers = (Convert-PackageManagerStatusToMap -PackageManagers $packageManagers -RootPath $rootPath)
        summary = [ordered]@{
            appCount = $apps.Count
            evidenceCount = @($Scan.evidence).Count
            classificationSummary = (Get-ClassificationSummary -Apps $apps)
            restoreConfidenceSummary = (Get-ConfidenceSummary -Apps $apps)
            manualReinstallCount = $manualApps.Count
            unsupportedCount = $unsupportedApps.Count
        }
        apps = @($apps)
        manualReinstall = @($manualApps)
        unsupported = @($unsupportedApps)
    }

    Merge-LatestConfigBackupIntoManifest -Manifest $manifest -RootPath $rootPath | Out-Null
    return $manifest
}

function ConvertTo-MarkdownCell {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $clean = $Text -replace "[\r\n]+", " "
    return ($clean -replace "\|", "\|")
}

function Add-MapSummaryLines {
    param(
        [Parameter(Mandatory = $true)]
        $Lines,

        $Map
    )

    foreach ($key in (Get-ObjectKeys -Object $Map | Sort-Object)) {
        $value = Get-MapValue -Map $Map -Key $key
        $Lines.Add(("- {0}: {1}" -f $key, $value))
    }
}

function Convert-ManifestReportToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    $summary = Get-MapValue -Map $Manifest -Key "summary"
    $machine = Get-MapValue -Map $Manifest -Key "machine"
    $root = Get-MapValue -Map $Manifest -Key "root"
    $sourceScan = Get-MapValue -Map $Manifest -Key "sourceScan"
    $apps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps")
    $manualApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "manualReinstall")
    $unsupportedApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unsupported")
    $packageManagers = Get-MapValue -Map $Manifest -Key "packageManagers"

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# WinCarry Scan Report")
    $lines.Add("")
    $lines.Add(("Created: {0}" -f (Get-MapValue -Map $Manifest -Key "createdAt")))
    $lines.Add(("Manifest schema: {0}" -f (Get-MapValue -Map $Manifest -Key "schemaVersion")))
    $lines.Add(("WinCarry root: {0}" -f (Get-MapValue -Map $root -Key "winCarryRoot")))
    $lines.Add(("Offline-safe mode: {0}" -f [bool](Get-MapValue -Map $Manifest -Key "offlineSafeMode")))
    $lines.Add("")
    if ([bool](Get-MapValue -Map $Manifest -Key "offlineSafeMode")) {
        $lines.Add("> Offline-safe mode skipped package-manager scan/status commands. Package-manager restore commands are blocked for this manifest.")
        $lines.Add("")
    }
    $lines.Add("> Restore confidence is a risk classification, not a success rate or guarantee.")
    $lines.Add("")

    $lines.Add("## System")
    $lines.Add("")
    $lines.Add(("- Computer: {0}" -f (Get-MapValue -Map $machine -Key "computerName")))
    $lines.Add(("- Windows: {0}" -f (Get-MapValue -Map $machine -Key "windowsVersion")))
    $lines.Add(("- User: {0}\\{1}" -f (Get-MapValue -Map $machine -Key "userDomain"), (Get-MapValue -Map $machine -Key "userName")))
    $lines.Add(("- Profile: {0}" -f (Get-MapValue -Map $machine -Key "userProfile")))
    $lines.Add(("- Is admin/root: {0}" -f (Get-MapValue -Map $machine -Key "isAdmin")))
    $lines.Add("")

    $lines.Add("## Summary")
    $lines.Add("")
    $lines.Add(("- Apps: {0}" -f (Get-MapValue -Map $summary -Key "appCount")))
    $lines.Add(("- Evidence records: {0}" -f (Get-MapValue -Map $summary -Key "evidenceCount")))
    $lines.Add(("- Manual reinstall / review: {0}" -f (Get-MapValue -Map $summary -Key "manualReinstallCount")))
    $lines.Add(("- Unsupported / do not restore automatically: {0}" -f (Get-MapValue -Map $summary -Key "unsupportedCount")))
    $lines.Add("")

    $lines.Add("## Classification Summary")
    $lines.Add("")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "classificationSummary")
    $lines.Add("")

    $lines.Add("## Restore Confidence Summary")
    $lines.Add("")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "restoreConfidenceSummary")
    $lines.Add("")

    $lines.Add("## Package Managers")
    $lines.Add("")
    foreach ($managerName in (Get-ObjectKeys -Object $packageManagers | Sort-Object)) {
        $manager = Get-MapValue -Map $packageManagers -Key $managerName
        $available = Get-MapValue -Map $manager -Key "available"
        $version = [string](Get-MapValue -Map $manager -Key "version")
        if ([bool](Get-MapValue -Map $manager -Key "offlineSafeSkipped")) {
            $lines.Add(("- {0}: skipped by offline-safe mode" -f $managerName))
            continue
        }
        if ([string]::IsNullOrWhiteSpace($version)) {
            $version = "version unknown"
        }
        $lines.Add(("- {0}: available={1}; {2}" -f $managerName, $available, $version))
    }
    $lines.Add("")

    $warnings = ConvertTo-ArrayValue -Value (Get-MapValue -Map $sourceScan -Key "warnings")
    if ($warnings.Count -gt 0) {
        $lines.Add("## Scan Warnings")
        $lines.Add("")
        foreach ($warning in $warnings) {
            $lines.Add(("- {0}: {1}" -f (Get-MapValue -Map $warning -Key "source"), (Get-MapValue -Map $warning -Key "message")))
        }
        $lines.Add("")
    }

    $lines.Add("## Manual Reinstall / Review List")
    $lines.Add("")
    if ($manualApps.Count -eq 0) {
        $lines.Add("No manual reinstall/review apps recorded.")
    } else {
        $lines.Add("| App | Classification | Restore confidence | Package | Reason |")
        $lines.Add("| --- | --- | --- | --- | --- |")
        foreach ($app in $manualApps) {
            $lines.Add(("| {0} | {1} | {2} | {3} | {4} |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "classification")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "restoreConfidence")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "package")),
                (ConvertTo-MarkdownCell -Text (Get-AppReasonsText -App $app))))
        }
    }
    $lines.Add("")

    $lines.Add("## Unsupported / Do Not Restore Automatically")
    $lines.Add("")
    if ($unsupportedApps.Count -eq 0) {
        $lines.Add("No unsupported apps recorded.")
    } else {
        $lines.Add("| App | Classification | Reason |")
        $lines.Add("| --- | --- | --- |")
        foreach ($app in $unsupportedApps) {
            $lines.Add(("| {0} | {1} | {2} |" -f
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "name")),
                (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "classification")),
                (ConvertTo-MarkdownCell -Text (Get-AppReasonsText -App $app))))
        }
    }
    $lines.Add("")

    $lines.Add("## App Details")
    $lines.Add("")
    $lines.Add("| App | Classification | Restore confidence | Strategy | Package | Reasons | Warnings |")
    $lines.Add("| --- | --- | --- | --- | --- | --- | --- |")
    foreach ($app in $apps) {
        $lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "name")),
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "classification")),
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "restoreConfidence")),
            (ConvertTo-MarkdownCell -Text (Get-MapValue -Map $app -Key "restoreStrategy")),
            (ConvertTo-MarkdownCell -Text (Get-AppPackageSummaryText -App $app)),
            (ConvertTo-MarkdownCell -Text (Get-AppReasonsText -App $app)),
            (ConvertTo-MarkdownCell -Text (Get-AppWarningsText -App $app))))
    }
    $lines.Add("")

    $lines.Add("## Next Recommended Steps")
    $lines.Add("")
    $lines.Add("- Review unsupported and manual reinstall lists before formatting Windows.")
    $lines.Add("- Do not assume apps installed outside C: will run after reinstall without repair, login, activation, services, or registry state.")
    $lines.Add("- Prefer package-manager reinstall or portable/Scoop workflows for future apps that should survive reinstall more cleanly.")

    return ($lines -join [Environment]::NewLine)
}

function Convert-ManifestReportToText {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    $summary = Get-MapValue -Map $Manifest -Key "summary"
    $machine = Get-MapValue -Map $Manifest -Key "machine"
    $root = Get-MapValue -Map $Manifest -Key "root"
    $apps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "apps")
    $manualApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "manualReinstall")
    $unsupportedApps = ConvertTo-ArrayValue -Value (Get-MapValue -Map $Manifest -Key "unsupported")

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("WinCarry Scan Report")
    $lines.Add("")
    $lines.Add(("Created: {0}" -f (Get-MapValue -Map $Manifest -Key "createdAt")))
    $lines.Add(("Root: {0}" -f (Get-MapValue -Map $root -Key "winCarryRoot")))
    $lines.Add(("Offline-safe mode: {0}" -f [bool](Get-MapValue -Map $Manifest -Key "offlineSafeMode")))
    if ([bool](Get-MapValue -Map $Manifest -Key "offlineSafeMode")) {
        $lines.Add("Offline-safe note: package-manager scan/status commands were skipped, and package-manager restore commands are blocked for this manifest.")
    }
    $lines.Add(("Computer: {0}" -f (Get-MapValue -Map $machine -Key "computerName")))
    $lines.Add(("Windows: {0}" -f (Get-MapValue -Map $machine -Key "windowsVersion")))
    $lines.Add("")
    $lines.Add("Restore confidence is a risk classification, not a success rate or guarantee.")
    $lines.Add("")
    $lines.Add("Summary")
    $lines.Add(("- Apps: {0}" -f (Get-MapValue -Map $summary -Key "appCount")))
    $lines.Add(("- Evidence records: {0}" -f (Get-MapValue -Map $summary -Key "evidenceCount")))
    $lines.Add(("- Manual reinstall / review: {0}" -f $manualApps.Count))
    $lines.Add(("- Unsupported / do not restore automatically: {0}" -f $unsupportedApps.Count))
    $lines.Add("")

    $lines.Add("Classification Summary")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "classificationSummary")
    $lines.Add("")
    $lines.Add("Restore Confidence Summary")
    Add-MapSummaryLines -Lines $lines -Map (Get-MapValue -Map $summary -Key "restoreConfidenceSummary")
    $lines.Add("")

    $lines.Add("Manual Reinstall / Review List")
    foreach ($app in $manualApps) {
        $lines.Add(("- {0} [{1}, {2}] package={3}" -f (Get-MapValue -Map $app -Key "name"), (Get-MapValue -Map $app -Key "classification"), (Get-MapValue -Map $app -Key "restoreConfidence"), (Get-MapValue -Map $app -Key "package")))
        $lines.Add(("  Reason: {0}" -f (Get-AppReasonsText -App $app)))
    }
    if ($manualApps.Count -eq 0) {
        $lines.Add("- None")
    }
    $lines.Add("")

    $lines.Add("Unsupported / Do Not Restore Automatically")
    foreach ($app in $unsupportedApps) {
        $lines.Add(("- {0} [{1}]" -f (Get-MapValue -Map $app -Key "name"), (Get-MapValue -Map $app -Key "classification")))
        $lines.Add(("  Reason: {0}" -f (Get-AppReasonsText -App $app)))
    }
    if ($unsupportedApps.Count -eq 0) {
        $lines.Add("- None")
    }
    $lines.Add("")

    $lines.Add("App Details")
    foreach ($app in $apps) {
        $lines.Add(("- {0}" -f (Get-MapValue -Map $app -Key "name")))
        $lines.Add(("  Classification: {0}" -f (Get-MapValue -Map $app -Key "classification")))
        $lines.Add(("  Restore confidence: {0}" -f (Get-MapValue -Map $app -Key "restoreConfidence")))
        $lines.Add(("  Strategy: {0}" -f (Get-MapValue -Map $app -Key "restoreStrategy")))
        $lines.Add(("  Package: {0}" -f (Get-AppPackageSummaryText -App $app)))
        $lines.Add(("  Reasons: {0}" -f (Get-AppReasonsText -App $app)))
        $warnings = Get-AppWarningsText -App $app
        if (-not [string]::IsNullOrWhiteSpace($warnings)) {
            $lines.Add(("  Warnings: {0}" -f $warnings))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Convert-AppSummaryListToText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [object[]]$Apps
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($Title)
    $lines.Add("")
    if ($Apps.Count -eq 0) {
        $lines.Add("No entries.")
        return ($lines -join [Environment]::NewLine)
    }

    foreach ($app in $Apps) {
        $lines.Add(("- {0}" -f (Get-MapValue -Map $app -Key "name")))
        $lines.Add(("  Classification: {0}" -f (Get-MapValue -Map $app -Key "classification")))
        $lines.Add(("  Restore confidence: {0}" -f (Get-MapValue -Map $app -Key "restoreConfidence")))
        $lines.Add(("  Strategy: {0}" -f (Get-MapValue -Map $app -Key "restoreStrategy")))
        $lines.Add(("  Package: {0}" -f (Get-MapValue -Map $app -Key "package")))
        $lines.Add(("  Reasons: {0}" -f (Get-AppReasonsText -App $app)))
        $warnings = Get-AppWarningsText -App $app
        if (-not [string]::IsNullOrWhiteSpace($warnings)) {
            $lines.Add(("  Warnings: {0}" -f $warnings))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

