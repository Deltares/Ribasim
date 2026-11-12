<#
Build the DSD 2026 presentation "Coupling Ribasim & Wflow" from the Deltares template.

Drives PowerPoint through COM, so PowerPoint must be installed. Run make_all.py first:
the figures and their slide titles (figures/titles.json) come from there.

    .\build_deck.ps1 -TemplateDir "<folder with template_2.pptx and the DSD bio template>"
#>
param(
    [string]$TemplateDir = "$env:USERPROFILE\OneDrive - Stichting Deltares\Documents\Ribasim_development\dsd_2026",
    [string]$Output = (Join-Path $PSScriptRoot "wflow_ribasim_coupling_dsd2026.pptx")
)
$ErrorActionPreference = "Stop"

$Template = Join-Path $TemplateDir "template_2.pptx"
$BioTemplate = Get-ChildItem $TemplateDir -Filter "*presenter bio*.pptx" | Select-Object -First 1
$Figures = Join-Path $PSScriptRoot "figures"
$Titles = Get-Content (Join-Path $Figures "titles.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$TalkTitle = "Coupling Ribasim & Wflow"
$TalkSubtitle = "Enabling Land Processes and Irrigation"
$NameLine = "Hendrik Kok & Bart de Koning - 17 November 2026 - Delft"
$Footer = "Coupling Ribasim & Wflow - DSD 2026 - 17 November 2026"

# Geometry in points (72 per inch) on the 13.33 x 7.5 in template
$PT = 72
$Margin = 0.45 * $PT
$ContentTop = 1.45 * $PT
$ContentWidth = 12.44 * $PT
$ContentHeight = 5.45 * $PT
$SlideWidth = 13.333 * $PT
$SlideHeight = 7.5 * $PT

function Rgb([int]$r, [int]$g, [int]$b) { $r + 256 * $g + 65536 * $b }
$Navy = Rgb 8 12 128       # theme dk2
$Teal = Rgb 0 179 137      # theme accent4
$Grey = Rgb 89 89 89
$Light = Rgb 242 242 242   # theme lt2

Copy-Item $Template $Output -Force
$app = New-Object -ComObject PowerPoint.Application
$pres = $app.Presentations.Open($Output, $false, $false, $false)
try {
    # Keep only the title slide (1) and the "Anything else you'd like to ask?" slide (17)
    for ($i = $pres.Slides.Count; $i -ge 1; $i--) {
        if ($i -ne 1 -and $i -ne 17) { $pres.Slides($i).Delete() }
    }
    $endSlide = $pres.Slides(2)

    function Layout([string]$name) {
        foreach ($l in $pres.SlideMaster.CustomLayouts) { if ($l.Name.Trim() -eq $name) { return $l } }
        throw "Layout '$name' not found"
    }

    function New-Slide([string]$layout) {
        $pres.Slides.AddSlide($endSlide.SlideIndex, (Layout $layout))
    }

    function Set-Footer($slide) {
        $slide.HeadersFooters.Footer.Visible = -1
        $slide.HeadersFooters.Footer.Text = $Footer
        $slide.HeadersFooters.SlideNumber.Visible = -1
    }

    function Add-Text($slide, [string]$text, $left, $top, $width, $height, $size, $color, [bool]$bold = $false) {
        $box = $slide.Shapes.AddTextbox(1, $left, $top, $width, $height)
        $box.TextFrame.WordWrap = -1
        $box.TextFrame.MarginLeft = 0
        $box.TextFrame.MarginRight = 0
        $r = $box.TextFrame.TextRange
        $r.Text = $text
        $r.Font.Name = "Arial"
        $r.Font.Size = $size
        $r.Font.Color.RGB = $color
        $r.Font.Bold = [int]$bold
        $box
    }

    # Picture scaled to fit (left, top, width, height), centred in that box
    function Add-Picture($slide, [string]$file, $left, $top, $width, $height) {
        $pic = $slide.Shapes.AddPicture((Join-Path $Figures $file), 0, -1, $left, $top)
        $pic.LockAspectRatio = -1
        $scale = [Math]::Min($width / $pic.Width, $height / $pic.Height)
        $pic.Width = $pic.Width * $scale
        $pic.Left = $left + ($width - $pic.Width) / 2
        $pic.Top = $top + ($height - $pic.Height) / 2
        $pic.AlternativeText = $file
        $pic
    }

    function Add-ContentSlide([string]$file, [string]$title = $null, [string]$subtitle = $null) {
        $meta = $Titles.$file
        if (-not $title) { $title = $meta.title }
        if (-not $subtitle) { $subtitle = $meta.subtitle }
        $s = New-Slide "Alleen titel"
        $s.Shapes.Title.TextFrame.TextRange.Text = $title
        if ($subtitle) { [void](Add-Text $s $subtitle $Margin (0.98 * $PT) $ContentWidth (0.4 * $PT) 16 $Grey) }
        if ($file) { [void](Add-Picture $s $file $Margin $ContentTop $ContentWidth $ContentHeight) }
        Set-Footer $s
        $s
    }

    function Add-FullSlide([string]$file) {
        $s = New-Slide "Leeg"
        $s.HeadersFooters.Footer.Visible = 0  # the image covers the whole slide
        $s.HeadersFooters.SlideNumber.Visible = 0
        [void](Add-Picture $s $file 0 0 $SlideWidth $SlideHeight)
        $s
    }

    # ---------------------------------------------------------------- title and end slide
    $titleSlide = $pres.Slides(1)
    $t = $titleSlide.Shapes("Titel 25")
    $t.TextFrame.AutoSize = 0
    $t.TextFrame.VerticalAnchor = 1  # top, so a second line grows downwards, not into the photo
    $t.Top = 408
    $t.Height = 66
    $t.TextFrame.TextRange.Text = "$TalkTitle`r$TalkSubtitle"
    $t.TextFrame.TextRange.Paragraphs(1).Font.Size = 32
    $t.TextFrame.TextRange.Paragraphs(2).Font.Size = 22
    $t.TextFrame.TextRange.Paragraphs(2).Font.Bold = 0
    $titleSlide.Shapes("Ondertitel 26").Top = 488
    $titleSlide.Shapes("Ondertitel 26").TextFrame.TextRange.Text = $NameLine
    $endSlide.Shapes("Ondertitel 26").TextFrame.TextRange.Text = $NameLine

    # ---------------------------------------------------------------- Hendrik
    [void](Add-ContentSlide "01_combined_strengths.png")
    [void](Add-FullSlide "02a_concept_wflow.png")
    [void](Add-FullSlide "02b_concept_coupled.png")
    [void](Add-ContentSlide "03_piave_grid_to_network.png")

    $half = ($ContentWidth - 0.3 * $PT) / 2
    $s = Add-ContentSlide "06_river_exchange.png" -subtitle "Left: monthly outflow at the Piave outlet, 2010-2014. Right: daily exchange Wflow to Ribasim, July 2010"
    $s.Shapes($s.Shapes.Count).Delete()  # the full-width picture; re-added on both halves
    [void](Add-Picture $s "08_outlet_discharge.png" $Margin $ContentTop $half $ContentHeight)
    [void](Add-Picture $s "06_river_exchange.png" ($Margin + $half + 0.3 * $PT) $ContentTop $half $ContentHeight)

    # ---------------------------------------------------------------- Bart
    [void](Add-FullSlide "02c_concept_irrigation.png")
    [void](Add-ContentSlide "04_irrigation_cells_to_userdemand.png")
    [void](Add-ContentSlide "05_coupled_timestep_cycle.png")
    [void](Add-ContentSlide "07_irrigation_loop.png")

    # Take-home messages: two cards with a numbered circle
    $s = Add-ContentSlide $null "Take-home messages" "Proof of concept on the Piave catchment"
    $messages = @(
        @("Each model does its part", "Wflow computes overland and subsurface flow and irrigation demand per grid cell. Ribasim routes, manages and allocates the water."),
        @("Water is conserved", "Everything Wflow hands over arrives in Ribasim, every day.")
    )
    $cardW = ($ContentWidth - 0.4 * $PT) / 2
    $cardH = 3.2 * $PT
    $cardTop = $ContentTop + 0.6 * $PT
    for ($k = 0; $k -lt $messages.Count; $k++) {
        $x = $Margin + $k * ($cardW + 0.4 * $PT)
        $card = $s.Shapes.AddShape(5, $x, $cardTop, $cardW, $cardH)
        $card.Fill.ForeColor.RGB = $Light
        $card.Line.Visible = 0
        $card.Adjustments.Item(1) = 0.08
        $card.Name = "Message $($k + 1)"
        $dot = $s.Shapes.AddShape(9, $x + 0.4 * $PT, $cardTop + 0.4 * $PT, 0.8 * $PT, 0.8 * $PT)  # oval
        $dot.Fill.ForeColor.RGB = $Teal
        $dot.Line.Visible = 0
        $dot.TextFrame.TextRange.Text = "$($k + 1)"
        $dot.TextFrame.TextRange.Font.Name = "Arial"
        $dot.TextFrame.TextRange.Font.Size = 28
        $dot.TextFrame.TextRange.Font.Bold = -1
        $dot.TextFrame.TextRange.Font.Color.RGB = (Rgb 255 255 255)
        $dot.Name = "Number $($k + 1)"
        [void](Add-Text $s $messages[$k][0] ($x + 0.4 * $PT) ($cardTop + 1.45 * $PT) ($cardW - 0.8 * $PT) (0.5 * $PT) 26 $Navy $true)
        [void](Add-Text $s $messages[$k][1] ($x + 0.4 * $PT) ($cardTop + 2.05 * $PT) ($cardW - 0.8 * $PT) (1.0 * $PT) 18 $Grey)
    }

    # ---------------------------------------------------------------- backup (after the end slide)
    $divider = $pres.Slides.AddSlide($pres.Slides.Count + 1, (Layout "Hoofdstuk"))
    $divider.Shapes.Title.TextFrame.TextRange.Text = "Backup"
    Set-Footer $divider
    $backup = @(
        "backup/b1_coupling_water_balance.png",
        "backup/b4_irrigation_results.png",
        "backup/b2_modular_wflow.png",
        "backup/b3a_pr3324_mapping.png",
        "backup/b3b_pr3333_schematization.png"
    )
    # Shorter titles where the figure's own title is too long for one line
    $backupTitles = @{ "backup/b4_irrigation_results.png" = "Irrigation results per UserDemand" }
    foreach ($file in $backup) {
        $meta = $Titles.$file
        if ($backupTitles.ContainsKey($file)) { $meta = @{ title = $backupTitles[$file]; subtitle = $meta.subtitle } }
        $s = $pres.Slides.AddSlide($pres.Slides.Count + 1, (Layout "Alleen titel"))
        $s.Shapes.Title.TextFrame.TextRange.Text = $meta.title
        if ($meta.subtitle) { [void](Add-Text $s $meta.subtitle $Margin (0.98 * $PT) $ContentWidth (0.4 * $PT) 16 $Grey) }
        [void](Add-Picture $s $file $Margin $ContentTop $ContentWidth $ContentHeight)
        Set-Footer $s
    }

    # ---------------------------------------------------------------- bio slides (shown by the host, first)
    if ($BioTemplate) {
        $people = @(
            @("Hendrik Kok", "[Position], Deltares"),
            @("Bart de Koning", "[Position], Deltares")
        )
        for ($k = $people.Count - 1; $k -ge 0; $k--) {
            [void]$pres.Slides.InsertFromFile($BioTemplate.FullName, 0, 1, 1)
            $bio = $pres.Slides(1)
            $name = $bio.Shapes("Title 1")
            $name.TextFrame.WordWrap = 0  # the template box is narrow; keep the name on one line
            $name.TextFrame.TextRange.Text = $people[$k][0]
            $name.TextFrame.AutoSize = 0
            $name.TextFrame.VerticalAnchor = 4  # bottom, directly above the position line
            $name.Height = 40
            $name.Top = $bio.Shapes("Rectangle 7").Top - $name.Height
            $bio.Shapes("TextBox 4").TextFrame.TextRange.Text = "$TalkTitle`: $TalkSubtitle"
            $bio.Shapes("Rectangle 7").TextFrame.TextRange.Text = $people[$k][1]
            $bio.Shapes("TextBox 6").TextFrame.TextRange.Text = "[Short bio to follow]"
        }
    }

    $pres.Save()
    "Saved $Output with $($pres.Slides.Count) slides"
} finally {
    $pres.Close()
    if ($app.Presentations.Count -eq 0) { $app.Quit() }
}
