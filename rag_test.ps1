$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$doc = Get-Content (Join-Path $dir "politica_innovatech_2027.txt") -Raw -Encoding UTF8

function Invoke-Ollama($path, $obj) {
    $json = $obj | ConvertTo-Json -Depth 6
    Invoke-RestMethod -Uri "http://localhost:11434$path" -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType "application/json; charset=utf-8" -TimeoutSec 300
}
function Get-Embedding($text) { (Invoke-Ollama "/api/embeddings" @{model="nomic-embed-text"; prompt=$text}).embedding }
function Get-Cosine($a, $b) {
    $dot=0.0;$na=0.0;$nb=0.0
    for($i=0;$i -lt $a.Count;$i++){ $dot+=$a[$i]*$b[$i]; $na+=$a[$i]*$a[$i]; $nb+=$b[$i]*$b[$i] }
    $dot/([Math]::Sqrt($na)*[Math]::Sqrt($nb))
}

# Chunking: un fragmento por seccion numerada, mas el encabezado
$parts = $doc -split "\r?\n\r?\n" | Where-Object { $_.Trim() }
$chunks = @()
foreach($p in $parts[1..($parts.Count-1)]) { $chunks += ,@{text=$p.Trim(); emb=(Get-Embedding ("search_document: " + $p.Trim()))} }
"Indexados {0} fragmentos`n" -f $chunks.Count

$tests = @(
  @{n="Prompt 1 (Conocimiento privado)"; q="¿De cuánto es el auxilio de conectividad para teletrabajo en 2027 en Innovatech Colombia y cuál es el código interno para solicitarlo?"},
  @{n="Dato Exacto"; q="¿Cuánto es el auxilio de conectividad 2027 y cuál es su código?"},
  @{n="Condicional / Rol"; q="Llevo 8 meses en la empresa, ¿cuántos días de vacaciones anticipadas puedo pedir y quién gestiona RRHH?"},
  @{n="Protocolo Tecnico"; q="Detecté una fuga en AWS, ¿en cuánto tiempo debo reportarla, a qué canal y qué cifrado exige la norma?"},
  @{n="Anti-Alucinacion"; q="¿Cuál es el horario de atención de la cafetería los sábados en Innovatech?"}
)

$out = @()
foreach($t in $tests) {
  $qe = Get-Embedding ("search_query: " + $t.q)
  $ranked = $chunks | ForEach-Object { [pscustomobject]@{score=(Get-Cosine $qe $_.emb); text=$_.text} } | Sort-Object score -Descending
  $top = $ranked | Select-Object -First 2
  $ctx = ($top | ForEach-Object { "[Fragmento] " + $_.text }) -join "`n`n"
  $sys = "Eres un asistente interno. Responde SOLO con base en el contexto proporcionado. Si el contexto no contiene la respuesta, responde exactamente que el documento no contiene esa información. Cita el documento como fuente.`n`n<context>`n$ctx`n</context>"
  $r = Invoke-Ollama "/api/chat" @{model="qwen2.5:1.5b-instruct"; stream=$false; options=@{temperature=0.1}; messages=@(@{role="system";content=$sys},@{role="user";content=$t.q})}
  $block = "=== {0} ===`nPregunta: {1}`nFragmentos (score): {2}`nRespuesta:`n{3}`n" -f $t.n,$t.q,(($top | ForEach-Object { "{0:N3}" -f $_.score }) -join ", "),$r.message.content
  $block; $out += $block
}
$out -join "`n" | Set-Content (Join-Path $dir "resultado_con_rag.txt") -Encoding UTF8
