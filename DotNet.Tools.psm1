<#
Copyright 2019 Arnold Clark Automobiles Ltd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and 
associated documentation files (the "Software"), to deal in the Software without restriction, 
including without limitation the rights to use, copy, modify, merge, publish, distribute, 
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is 
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#>

function Invoke-DotNetTest
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]
        $Path = (Get-Location),

        [Parameter()]
        [string]
        $Tool = "coverlet.msbuild",

        [Parameter()]
        [switch]
        $Recurse,

        [Parameter()]
        [switch]
        $CodeCoverage,

        [Parameter()]
        [switch]
        $GenerateReport,

        [Parameter()]
        [string]
        $CoverletOutputFormat = 'cobertura'
    )

    $args = @()

    # Test dependencies, fail early
    Get-Command -Name 'dotnet.exe' -CommandType Application -ErrorAction Stop | Out-Null

    if($GenerateReport -and -not $CodeCoverage) {
        throw "-GenerateReport parameter is only valid when -CodeCoverage parameter is also present."
    }

    $reportTool = Get-Command "reportgenerator" -ErrorAction SilentlyContinue
    if($GenerateReport.IsPresent -and -not $reportTool) {
        dotnet tool install --global dotnet-reportgenerator-globaltool
    }
    elseif($GenerateReport.IsPresent) {
        dotnet tool update --global dotnet-reportgenerator-globaltool
    }

    $mergeWith = @()
    function Get-MergeWith {
        $mergeWith | ForEach-Object {
            "/p:MergeWith=""$($_)"""
        }
    }

    function Get-Args {
        param(
            [switch]
            $Last
        )

        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
            $args += "--verbosity normal"
        }
        if($CodeCoverage.IsPresent) {
            $args += "/p:CollectCoverage=true"

            if($Last.IsPresent){
                $args += "/p:CoverletOutputFormat=$CoverletOutputFormat" 
            }

            $args += Get-MergeWith
        }
    }

    if((Get-Item -Path $Path -ErrorAction Stop) -is [System.IO.FileInfo]) {
        $Path = $info.Directory.FullName
    }

    $projects = Get-ChildItem -Path $Path -Filter '*.csproj' -Recurse:$Recurse |
        Where-Object {
            $xml = [xml](Get-Content -Path $_.FullName)
            $null -ne ($xml.Project.ItemGroup.PackageReference | Where-Object Include -eq 'Microsoft.NET.Test.Sdk') -and
            $null -ne ($xml.Project.ItemGroup.PackageReference | Where-Object Include -eq $Tool)
        }

    if (-not $projects) {
        throw "Could not find any dotnet project files in provided path: $Path"
    }

    $projects | Select-Object -SkipLast 1 | ForEach-Object {
        Get-ChildItem -Path $_.Directory -Filter "coverage.json" -File | Remove-Item
        $args = Get-Args
        Write-Verbose "Running: dotnet test $args $($_.FullName)"
        & dotnet test (Get-Args) ""$($_.FullName)""
        $mergeWith += "$($_.Directory)/coverage.json"
    }

    $projects | Select-Object -Last 1 | ForEach-Object {
        Get-ChildItem -Path $Path -Filter TestCoverage -Directory | Remove-Item -Recurse:$Recurse
        Write-Verbose "Running: dotnet test $args $($_.FullName)"
        & dotnet test (Get-Args -Last) ""$($_.FullName)""

        if($GenerateReport.IsPresent){
            & reportgenerator -reports:$(Join-Path `
                -Path $_.Directory `
                -ChildPath "coverage.$CoverletOutputFormat.xml") `
                -targetdir:$Path/TestCoverage `
                -reportTypes:htmlInline
        }
    }

    if ($GenerateReport -and
        -not ([Environment]::GetCommandLineArgs() -contains '-NonInteractive')) {
        & "$Path/TestCoverage/index.htm"
    }
}