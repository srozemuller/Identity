function Create-UrlListBatchOutput {
    param (
        [System.Collections.Generic.List[string]] $urlList,
        [string] $Method,
        [string] $Body
    )
    if ($Method -eq 'POST' -and -not $Body) {
        throw 'Body is required for POST requests'
    }
    $chunks = Chunk-List $urlList 20
    $outputJsonStrings = @()

    foreach ($chunk in $chunks) {
        $outputObject = @{
            requests = @()
        }

        $requestId = 1
        foreach ($urlValue in $chunk) {
            $request = @{
                id = $requestId++
                method = $Method
                url = $urlValue
            }
            if ($Body) {
                $request.Add('body',$Body)
            }
            $outputObject.requests += $request
        }
        $outputJsonStrings += ($outputObject | ConvertTo-Json)
    }
    return ,$outputJsonStrings
}

function Create-BodyList {
    param (
        [System.Collections.Generic.List[string]] $bodyList
    )
    $chunks = Chunk-List $bodyList 20
    $outputJsonStrings = [System.Collections.ArrayList]@()

    foreach ($chunk in $chunks) {
        $outputObject = @{
            'members@odata.bind' = @()
        }

        foreach ($bodyValue in $chunk) {

            $outputObject.'members@odata.bind' += $bodyValue
        }
        $outputJsonStrings.Add($outputObject) >> $null
    }
    return ,$outputJsonStrings
}
function Chunk-List {
    param (
        [System.Collections.Generic.List[string]] $list,
        [int] $chunkSize
    )

    $chunks = @()
    for ($i = 0; $i -lt $list.Count; $i += $chunkSize) {
        $chunks += ,$list[$i..($i + $chunkSize - 1)]
    }
    return ,$chunks
}