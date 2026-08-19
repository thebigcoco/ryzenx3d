param([switch]$UseGitHeadEvidence)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $repoRoot 'index.html'
$metaPath = Join-Path $repoRoot 'report-meta.json'
$html = [System.IO.File]::ReadAllText($indexPath)
$taipeiOffset = [TimeSpan]::FromHours(8)

function Get-Cells([string]$rowHtml) {
    return [regex]::Matches($rowHtml, '<td>([\s\S]*?)</td>')
}

function Get-PostId([string]$rowHtml) {
    return [regex]::Match($rowHtml, 'href="[^"]*/comments/([a-z0-9]+)/', 'IgnoreCase').Groups[1].Value
}

function Get-PostMetadata([string[]]$ids) {
    $result = @{}
    $uniqueIds = @($ids | Where-Object { $_ } | Sort-Object -Unique)
    for ($offset = 0; $offset -lt $uniqueIds.Count; $offset += 50) {
        $end = [Math]::Min($offset + 49, $uniqueIds.Count - 1)
        $chunk = $uniqueIds[$offset..$end]
        $url = 'https://arctic-shift.photon-reddit.com/api/posts/ids?ids=' + ($chunk -join ',')
        $response = Invoke-RestMethod -Uri $url
        foreach ($post in $response.data) {
            $result[$post.id] = $post
        }
        Start-Sleep -Milliseconds 500
    }
    return $result
}

function Format-TaipeiTime([long]$unixTime) {
    $local = [DateTimeOffset]::FromUnixTimeSeconds($unixTime).ToOffset($taipeiOffset)
    return $local.ToString('yyyy-MM-dd') + '<br><span class="case-time">' + $local.ToString('HH:mm:ss') + '</span>'
}

function Format-Author([string]$author) {
    if ([string]::IsNullOrWhiteSpace($author) -or $author -eq '[deleted]') {
        return '<span class="small">[deleted]</span>'
    }
    $encoded = [System.Net.WebUtility]::HtmlEncode($author)
    $profile = 'https://www.reddit.com/user/' + [uri]::EscapeDataString($author) + '/'
    return '<a href="' + $profile + '" target="_blank" rel="noopener">u/' + $encoded + '</a>'
}

$combinedMatch = [regex]::Match($html, '<table id="combined-cases">[\s\S]*?</table>')
$combinedTable = $combinedMatch.Value
$combinedRows = [regex]::Matches($combinedTable, '<tr>([\s\S]*?)</tr>')
$combinedItems = @()
for ($i = 1; $i -lt $combinedRows.Count; $i++) {
    $row = $combinedRows[$i].Groups[1].Value
    $combinedItems += [pscustomobject]@{
        Row = $row
        Id = Get-PostId $row
    }
}

$evidenceTargetMatch = [regex]::Match($html, '<table id="evidence-table"[\s\S]*?</table>')
$evidenceSourceHtml = if ($UseGitHeadEvidence) { (& git -C $repoRoot show HEAD:index.html) -join "`n" } else { $html }
$evidenceMatch = [regex]::Match($evidenceSourceHtml, '<table id="evidence-table"[\s\S]*?</table>')
$evidenceTable = $evidenceMatch.Value
$evidenceRows = [regex]::Matches($evidenceTable, '<tr>([\s\S]*?)</tr>')
$evidenceItems = @()
for ($i = 1; $i -lt $evidenceRows.Count; $i++) {
    $row = $evidenceRows[$i].Groups[1].Value
    $evidenceItems += [pscustomobject]@{
        OriginalIndex = $i
        Row = $row
        Id = Get-PostId $row
    }
}

$allIds = @($combinedItems.Id + $evidenceItems.Id)
$postMap = Get-PostMetadata $allIds

$combinedOutput = @()
foreach ($item in $combinedItems) {
    $cells = Get-Cells $item.Row
    $post = $postMap[$item.Id]
    if (-not $post) { throw "Missing post metadata: $($item.Id)" }
    $unix = [long]$post.created_utc
    $parts = @('<td>' + (Format-TaipeiTime $unix) + '</td>', '<td>' + (Format-Author $post.author) + '</td>')
    $contentStart = if ($cells.Count -eq 8) { 2 } elseif ($cells.Count -eq 7) { 1 } else { throw "Unexpected combined cell count: $($cells.Count)" }
    for ($j = $contentStart; $j -lt $cells.Count; $j++) {
        $parts += '<td>' + $cells[$j].Groups[1].Value + '</td>'
    }
    $combinedOutput += [pscustomobject]@{
        Unix = $unix
        Html = '<tr>' + ($parts -join '') + '</tr>'
    }
}
$combinedOutput = @($combinedOutput | Sort-Object Unix -Descending)
$combinedHeader = '<thead><tr><th>發文時間（台灣）</th><th>Reddit 使用者</th><th>CPU</th><th>主機板</th><th>Subreddit</th><th>原文標題</th><th>案例類別</th><th>原文證據</th><th>信心／位置</th></tr></thead>'
$newCombinedTable = '<table id="combined-cases">' + "`r`n" + $combinedHeader + "`r`n<tbody>" + (($combinedOutput.Html) -join '') + '</tbody>' + "`r`n</table>"
$html = $html.Remove($combinedMatch.Index, $combinedMatch.Length).Insert($combinedMatch.Index, $newCombinedTable)

$commentMap = @{
    18 = @{ id = 'p375euz'; author = 'MF_Kitten'; created_utc = 1786520811; subreddit = 'ASRock'; post = '1vm2vc1' }
    21 = @{ id = 'p10lqs3'; author = 'Toast_Meat'; created_utc = 1785561205; subreddit = 'pcmasterrace'; post = '1vcdtbm' }
    26 = @{ id = 'p07mr6v'; author = 'Zefiris8'; created_utc = 1785218346; subreddit = 'ASRock'; post = '1v8jzqo' }
    27 = @{ id = 'p07ja1v'; author = 'kaspersky2017'; created_utc = 1785216729; subreddit = 'ASRock'; post = '1v8jzqo' }
    28 = @{ id = 'p09emta'; author = 'DedPixl89'; created_utc = 1785245257; subreddit = 'ASRock'; post = '1v8jzqo' }
    29 = @{ id = 'ots25ob'; author = 'Positive-Love-3240'; created_utc = 1782412472; subreddit = 'ASUS'; post = '1rh668y' }
    30 = @{ id = 'ov6tdrr'; author = 'monkeybuiltpc'; created_utc = 1783023819; subreddit = 'ASUS'; post = '1uka1k1' }
    31 = @{ id = 'ouut9jo'; author = 'imp3rd1349'; created_utc = 1782884475; subreddit = 'ASUS'; post = '1uka1k1' }
}
$commentById = @{}
foreach ($entry in $commentMap.Values) { $commentById[$entry.id] = $entry }

$evidenceOutput = @()
foreach ($item in $evidenceItems) {
    $cells = Get-Cells $item.Row
    $sourceIndex = $cells.Count - 1
    $contentStart = if ($cells.Count -eq 9) { 2 } elseif ($cells.Count -eq 8) { 1 } else { throw "Unexpected evidence cell count: $($cells.Count)" }
    $sourceHtml = $cells[$sourceIndex].Groups[1].Value
    $isUnknownMegathread = $item.Row -match '9800X3D Failures/Deaths Megathread'
    $existingCommentId = [regex]::Match($sourceHtml, '/_/([a-z0-9]+)/', 'IgnoreCase').Groups[1].Value
    $comment = if ($isUnknownMegathread) { $null } elseif ($existingCommentId) { $commentById[$existingCommentId] } elseif ($cells.Count -eq 8) { $commentMap[$item.OriginalIndex] } else { $null }
    if ($comment) {
        $unix = [long]$comment.created_utc
        $authorHtml = Format-Author $comment.author
        $permalink = 'https://www.reddit.com/r/' + $comment.subreddit + '/comments/' + $comment.post + '/_/' + $comment.id + '/'
        $sourceHtml = '<a href="' + $permalink + '" target="_blank" rel="noopener">原始留言</a>'
    } elseif ($isUnknownMegathread) {
        $unix = [DateTimeOffset]::Parse('2025-04-27T00:00:00+08:00').ToUnixTimeSeconds()
        $authorHtml = '<span class="small">留言作者未確認</span>'
        $sourceHtml = '<a href="https://www.reddit.com/r/ASRock/comments/1iui7lx/" target="_blank" rel="noopener">原始貼文</a>'
    } else {
        $post = $postMap[$item.Id]
        if (-not $post) { throw "Missing evidence post metadata: $($item.Id)" }
        $unix = [long]$post.created_utc
        $authorHtml = Format-Author $post.author
    }

    $timeText = if ($isUnknownMegathread) { '2025-04-27（留言時間未確認）' } else { Format-TaipeiTime $unix }
    $parts = @('<td>' + $timeText + '</td>', '<td>' + $authorHtml + '</td>')
    for ($j = $contentStart; $j -lt $sourceIndex; $j++) {
        $cellHtml = $cells[$j].Groups[1].Value
        if ($item.Id -eq '1vq97nd' -and $j -eq ($sourceIndex - 1)) {
            $cellHtml = '貼文正文／中／有證據燒掉'
        }
        $parts += '<td>' + $cellHtml + '</td>'
    }
    $parts += '<td>' + $sourceHtml + '</td>'
    $evidenceOutput += [pscustomobject]@{
        Unix = $unix
        Html = '<tr>' + ($parts -join '') + '</tr>'
    }
}
$evidenceOutput = @($evidenceOutput | Sort-Object Unix -Descending)
$evidenceHeader = '<thead><tr><th>發文／留言時間（台灣）</th><th>Reddit 使用者</th><th>CPU</th><th>主機板</th><th>Subreddit</th><th>原文標題</th><th>原文證據</th><th>位置／強度</th><th>來源</th></tr></thead>'
$newEvidenceTable = '<table id="evidence-table" class="evidence-table">' + "`r`n" + $evidenceHeader + "`r`n<tbody>" + (($evidenceOutput.Html) -join '') + '</tbody></table>'
$html = $html.Remove($evidenceTargetMatch.Index, $evidenceTargetMatch.Length).Insert($evidenceTargetMatch.Index, $newEvidenceTable)

$html = $html.Replace('日期約為 2025-06-24～2026-06-23', '發文時間（台灣）約為 2025-06-25～2026-06-23')
$combinedSummary = '<p>母表的 Detailed results 共 <b>207 筆貼文</b>；本表已依 Reddit <code>created_utc</code> 轉為台灣時間並重新排序，發文時間（台灣）約為 2025-06-25～2026-06-23；CPU 分布為：9950X3D 30 筆、9800X3D 139 筆、7800X3D 28 筆、7900X3D 2 筆、9800X3DS 2 筆、7950X3D 5 筆、9900X3D 1 筆。母表的 Global results 顯示品牌合計：ASRock 145、ASUS 44、MSI 11、Gigabyte 7，合計 207。</p>'
$html = [regex]::Replace($html, '<p>母表的 Detailed results 共 <b>207 筆貼文</b>[\s\S]*?母表的 Global results 顯示品牌合計：ASRock 145、ASUS 44、MSI 11、Gigabyte 7，合計 207。</p>', $combinedSummary, 1)
$html = $html.Replace('<p class="small">下列引文保留 Reddit 原文，僅摘錄能直接支持 CPU 型號、主機板、故障現象或驗證結果的短句；「正文／留言」表示引文所在位置。</p>', '<p class="small">下列引文保留 Reddit 原文；時間以 <code>created_utc</code> 轉為台灣時間（UTC+8）。貼文作者直接取自貼文 metadata；留言作者以真實 comment ID 核對。舊 megathread 有 1 筆未保留 comment ID，明確標示為「留言作者未確認」。</p>')

$generatedAt = [DateTimeOffset]::Now.ToOffset($taipeiOffset).ToString('yyyy-MM-dd HH:mm')
$html = [regex]::Replace($html, '搜尋及整理日期：\d{4}-\d{2}-\d{2} \d{2}:\d{2}', '搜尋及整理日期：' + $generatedAt, 1)

[System.IO.File]::WriteAllText($indexPath, $html, [System.Text.UTF8Encoding]::new($false))
$meta = Get-Content -Raw $metaPath | ConvertFrom-Json
$meta.generated_at = $generatedAt
[System.IO.File]::WriteAllText($metaPath, ($meta | ConvertTo-Json -Depth 4) + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Output "Updated combined rows: $($combinedOutput.Count)"
Write-Output "Updated evidence rows: $($evidenceOutput.Count)"
Write-Output "Generated at: $generatedAt"
