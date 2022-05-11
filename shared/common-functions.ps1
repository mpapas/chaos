<#
    Generates a short id from an integer.
    Ex. Get-ShortId(Get-Random)
#>
function Get-ShortId {
    param (
        [int32]$integer
    )

    $chars="0123456789ACEFHJKLMNPRTUVWXY"
    $length=$chars.length
    $result=""; $remain=[int]$integer
    do {
       $pos = $remain % $length
       $remain = [int][Math]::Floor($remain / $length)
       $result = $chars[$pos] + $result
    } while ($remain -gt 0)
    $result
}

function Get-ResourceName {
    param (
        [string]$Delimeter,
        [string]$Prefix,
        [string]$Middle,
        [string]$Suffix
    )
    $result = $Prefix + $Delimeter + $GeneratedValue + $Delimeter + $Suffix
    return $result
}

