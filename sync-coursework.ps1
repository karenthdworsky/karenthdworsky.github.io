# Syncs new lab HTML files from csu-523c/docs/ into coursework.qmd,
# then renders and pushes the personal site.
#
# Usage: .\sync-coursework.ps1
# Run from: C:\PhD\GitHub\karenthdworsky.github.io

$personalSiteRoot = "C:\PhD\GitHub\karenthdworsky.github.io"
$courseDocsDir    = "C:\PhD\Courses\WaterResources_Spring26\github\csu-523c\docs"
$courseworkFile   = Join-Path $personalSiteRoot "coursework.qmd"
$baseUrl          = "https://karenthdworsky.github.io/csu-523c"
$linkColor        = "#7ab3cc"
# Quarto is bundled inside RStudio and not on PATH by default
$quartoExe        = "C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe"

# --- Guard: must run from personal site root ---
if ((Get-Location).Path -ne $personalSiteRoot) {
    Write-Error "Run this from:`n  $personalSiteRoot"
    exit 1
}

# --- Discover rendered lab HTML files in course docs/ ---
# Matches lab-04.html, lab-05.html, etc. (lowercase kebab form after full render)
$renderedHtml = Get-ChildItem -Path $courseDocsDir -Filter "lab-*.html" -File |
    Where-Object { $_.Name -match '^lab-\d+\.html$' } |
    Sort-Object Name

if (-not $renderedHtml) {
    Write-Host "No lab-XX.html files found in $courseDocsDir. Nothing to sync."
    exit 0
}

# --- Read coursework.qmd ---
$content = Get-Content $courseworkFile -Raw

# --- Determine which lab NUMBERS are already listed (case-insensitive, any naming style) ---
# Matches LAB01.html, Lab02.html, lab-03.html, lab-04.html, etc.
$existingPattern = [regex]'(?i)href="https://karenthdworsky\.github\.io/csu-523c/[Ll][Aa][Bb]-?0*(\d+)[^"]*\.html"'
$existingLabNums = $existingPattern.Matches($content) |
    ForEach-Object { [int]$_.Groups[1].Value }

Write-Host "Labs currently in coursework.qmd: $($existingLabNums -join ', ')"

# --- Find labs in docs/ not yet in coursework.qmd ---
$newRows = @()
foreach ($file in $renderedHtml) {
    $labNum = [int]([System.IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '[^\d]', '')
    if ($existingLabNums -notcontains $labNum) {
        $htmlUrl = "$baseUrl/$($file.Name)"
        $newRows += [PSCustomObject]@{
            LabNum  = $labNum
            HtmlUrl = $htmlUrl
            Row     = "    <tr>`n      <td>Lab $labNum</td>`n      <td><!-- TODO: add topic for Lab $labNum --></td>`n      <td><a href=`"$htmlUrl`" style=`"color: $linkColor;`">View</a></td>`n    </tr>"
        }
        Write-Host "  + Adding: Lab $labNum ($($file.Name))" -ForegroundColor Green
    } else {
        Write-Host "  = Already listed: Lab $labNum ($($file.Name))" -ForegroundColor Gray
    }
}

if ($newRows.Count -eq 0) {
    Write-Host "coursework.qmd is already up to date." -ForegroundColor Cyan
} else {
    # Insert new rows before the closing </tbody> of the ESS 523c table.
    # Anchor: the paragraph link to the GitHub repo that immediately follows the table.
    $insertMarker = "</tbody>`n</table>`n`n<p style=`"margin-top: 1rem;`">"

    $sortedRows  = $newRows | Sort-Object LabNum
    $rowBlock    = ($sortedRows | ForEach-Object { $_.Row }) -join "`n"
    $replacement = "$rowBlock`n</tbody>`n</table>`n`n<p style=`"margin-top: 1rem;`">"

    $updatedContent = $content.Replace($insertMarker, $replacement)

    if ($updatedContent -eq $content) {
        # Try the indented variant (4-space)
        $insertMarker2  = "    </tbody>`n  </table>`n`n<p style=`"margin-top: 1rem;`">"
        $replacement2   = "$rowBlock`n    </tbody>`n  </table>`n`n<p style=`"margin-top: 1rem;`">"
        $updatedContent = $content.Replace($insertMarker2, $replacement2)
    }

    if ($updatedContent -eq $content) {
        Write-Warning "Could not locate the ESS 523c table closing tag. Check coursework.qmd formatting."
        exit 1
    }

    Set-Content -Path $courseworkFile -Value $updatedContent -NoNewline
    Write-Host "coursework.qmd updated with $($newRows.Count) new lab(s)." -ForegroundColor Green
    Write-Host "  Remember to replace the TODO placeholders with real topic descriptions." -ForegroundColor Yellow
}

# --- Render personal site ---
Write-Host "`nRendering personal site..." -ForegroundColor Cyan
if (-not (Test-Path $quartoExe)) {
    Write-Error "Quarto not found at $quartoExe. Update `$quartoExe if RStudio was reinstalled."
    exit 1
}
& $quartoExe render

if ($LASTEXITCODE -ne 0) {
    Write-Error "quarto render failed. Fix errors before pushing."
    exit 1
}

# --- Git add / commit / push ---
$timestamp = Get-Date -Format "yyyy-MM-dd"
git add coursework.qmd docs/
git commit -m "sync: add newly rendered labs to coursework ($timestamp)"
git push

Write-Host "`nPersonal site updated and pushed." -ForegroundColor Green
