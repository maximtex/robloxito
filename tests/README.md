# Pruebas automáticas

Se ejecutan **fuera de Roblox** con el intérprete de [Luau](https://github.com/luau-lang/luau).
Rojo no incluye esta carpeta en el juego: `default.project.json` solo sincroniza
`src/shared`, `src/server` y `src/client`.

## Ejecutar

```bash
python tests/run_tests.py            # todas las baterías actuales
python tests/run_tests.py quest tutorial
python tests/run_tests.py --legacy   # además, las heredadas (ver abajo)
```

Hace falta Python 3 y el ejecutable de Luau (`luau.exe` en Windows). Cópialo en
`tools/luau/` (carpeta ignorada por git) o indica su carpeta con la variable de entorno
`LUAU_BIN`.

## Cómo funcionan

`run_tests.py` **monta** cada batería en `tests/.build/` (ignorada por git):

1. un entorno simulado de Roblox (`harness/`),
2. los módulos **reales** de `src/`, sustituyendo cada `require(...)` por el módulo
   incrustado,
3. el cuerpo de la prueba (`suites/`).

Así cada ejecución prueba el código actual. Ninguna batería accede a DataStores reales:
las de guardado usan un DataStore simulado en memoria.

| Batería | Qué comprueba |
|---|---|
| `sanctuary` | Santuario del Núcleo Cósmico: contrato de nombres, colisiones, zonas libres del mapa, flotación, órbitas sin cruces, animación |
| `sandbox`, `sandbox_early` | Modo prueba del tutorial: ninguna llamada al DataStore, perfil temporal, nunca se guarda |
| `tutorial` | Pasos, omitir, veteranos, carga fallida, dos jugadores |
| `persist` | Guardado y carga de energía y mejoras, fallos de carga y de guardado, perfiles antiguos |
| `quest` | Misiones, diarias y logros: reclamar una sola vez, reinicio diario, validación |
| `combat` | Daño, muerte única, reparto de recompensas, objetivos |
| `petcombat` | Habilidades de mascotas |
| `anim` | Animación de enemigos |
| `pose` | Articulaciones de los modelos de enemigos |

## Pruebas heredadas (`legacy/`)

`pettest`, `eggtest`, `zonetest`, `savetest`, `layouttest` y `stagetest` llevan dentro
**copias antiguas** de los módulos que probaban. Se conservan como referencia, pero **no
validan el código actual**. Para recuperarlas hay que separar su cuerpo en `suites/` y
montarlas desde `src/` como las demás.

## Modo prueba del tutorial (Studio)

`src/server/DevConfig.luau` se guarda en git con `TutorialSandbox = false`. Para probar
el tutorial desde cero sin tocar tu partida real:

1. Cambia `TutorialSandbox = false` por `true` (con `rojo serve` conectado se sincroniza).
2. Pulsa **Play** en Studio: verás el aviso «🧪 Modo prueba del tutorial».
3. Al terminar, vuelve a dejarlo en `false`. `run_tests.py` avisa si se ha quedado en `true`.

En una partida publicada se ignora siempre (`RunService:IsStudio()` es falso).
