"""Pruebas automáticas de REBIRTH CITY (fuera de Roblox).

Cada batería se MONTA en tests/.build/ a partir del código real de src/ (los `require`
se sustituyen por los módulos incrustados) junto con un entorno simulado
(tests/harness/) y el cuerpo de la prueba (tests/suites/), y se ejecuta con el
intérprete de Luau.

Uso:
    python tests/run_tests.py            # baterías actuales (código de src/)
    python tests/run_tests.py anim quest # solo algunas
    python tests/run_tests.py --legacy   # además, las heredadas (NO validan src/)

Intérprete: variable de entorno LUAU_BIN (carpeta con luau.exe / luau) o, por
defecto, tools/luau/ (ignorada por git).

Las pruebas heredadas (tests/legacy/) llevan dentro copias ANTIGUAS de módulos: se
conservan como referencia hasta convertirlas, pero no comprueban el código actual.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")
BUILD = os.path.join(TESTS, ".build")


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as handle:
        return handle.read()


def harness(name):
    return read("tests", "harness", name)


def suite(name):
    return read("tests", "suites", name)


REQUIRE = re.compile(r"require\(([^()]|\([^()]*\))*?\.(\w+)\)")


def mod(name, path):
    """Módulo real de src/ incrustado: cada require(...X) se sustituye por la variable X."""
    source = REQUIRE.sub(lambda match: match.group(2), read(*path.split("/")))
    return f"local {name} = (function()\n{source}\nend)()\n"


def check_no_require(source):
    bad = [line for line in source.splitlines() if "require(" in line and not line.strip().startswith("--")]
    assert not bad, bad[:5]
    return source


# Grupos de módulos que comparten varias baterías ----------------------------------------

BASE = [
    ("EconomyConfig", "src/shared/Config/EconomyConfig.luau"),
    ("Economy", "src/shared/Economy.luau"),
    ("RebirthConfig", "src/shared/Config/RebirthConfig.luau"),
    ("RebirthLogic", "src/shared/RebirthLogic.luau"),
    ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
    ("AdventureLogic", "src/shared/AdventureLogic.luau"),
    ("PetConfig", "src/shared/Config/PetConfig.luau"),
    ("PetMath", "src/shared/PetMath.luau"),
    ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
    ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
    ("PetCombatConfig", "src/shared/Config/PetCombatConfig.luau"),
    ("QuestConfig", "src/shared/Config/QuestConfig.luau"),
    ("GameEvents", "src/server/Util/GameEvents.luau"),
] + [
    # Premios, tienda y semana (campos Rewards, Shop y Weekly del guardado v6).
    ("RewardConfig", "src/shared/Config/RewardConfig.luau"),
    ("RewardLogic", "src/server/Util/RewardLogic.luau"),
    ("MonetizationConfig", "src/shared/Config/MonetizationConfig.luau"),
    ("MonetizationLogic", "src/shared/MonetizationLogic.luau"),
    ("LeaderboardLogic", "src/server/Util/LeaderboardLogic.luau"),
]
# Núcleos: SaveService los sanea y los guarda (necesita CoreLogic inicializado).
CORE = [
    ("CoreConfig", "src/shared/Config/CoreConfig.luau"),
    ("CoreLogic", "src/server/Util/CoreLogic.luau"),
]
CORE_INIT = "CoreLogic.init(CoreConfig, Economy, EconomyConfig)\n"
SERVICES_AFTER_GLUE = [
    ("EnergyService", "src/server/Services/EnergyService.luau"),
    ("UpgradeService", "src/server/Services/UpgradeService.luau"),
    ("QuestService", "src/server/Services/QuestService.luau"),
    ("TutorialService", "src/server/Services/TutorialService.luau"),
]


def services_suite(prelude, with_dev_config, body):
    """Persistencia real: SaveService + PlayerDataService + servicios de juego."""
    order = BASE + [
        ("TutorialConfig", "src/shared/Config/TutorialConfig.luau"),
        ("Constants", "src/shared/Constants.luau"),
    ]
    if with_dev_config:
        order.append(("DevConfig", "src/server/DevConfig.luau"))
    order += [
        ("RateLimiter", "src/server/Util/RateLimiter.luau"),
        ("QuestLogic", "src/server/Util/QuestLogic.luau"),
        ("TutorialLogic", "src/server/Util/TutorialLogic.luau"),
    ]
    out = list(prelude)
    out += [mod(n, p) for n, p in order + CORE]
    out.append("QuestLogic.init(QuestConfig, EnemyConfig, Economy)\nTutorialLogic.init(TutorialConfig)\n" + CORE_INIT)
    out += [mod("SaveService", "src/server/Services/SaveService.luau"), mod("PlayerDataService", "src/server/Services/PlayerDataService.luau")]
    out.append(harness("tutorial_glue.luau"))
    out += [mod(n, p) for n, p in SERVICES_AFTER_GLUE]
    out.append(body)
    return "\n".join(out)


# Recetas de cada batería -------------------------------------------------------------

def persist_suite(body, extra=(), after_glue=()):
    order = BASE + [
        ("Constants", "src/shared/Constants.luau"),
        ("DevConfig", "src/server/DevConfig.luau"),
        ("RateLimiter", "src/server/Util/RateLimiter.luau"),
        ("QuestLogic", "src/server/Util/QuestLogic.luau"),
        ("TutorialConfig", "src/shared/Config/TutorialConfig.luau"),
        ("TutorialLogic", "src/server/Util/TutorialLogic.luau"),
    ] + CORE + [
        ("SaveService", "src/server/Services/SaveService.luau"),
    ] + list(extra) + [
        ("PlayerDataService", "src/server/Services/PlayerDataService.luau"),
    ]
    out = [harness("persist_stubs.luau")]
    for n, p in order:
        out.append(mod(n, p))
        if n == "TutorialLogic":
            out.append("TutorialLogic.init(TutorialConfig)\n")
        if n == "CoreLogic":
            out.append(CORE_INIT)
    out.append(harness("persist_glue.luau"))
    out.append(mod("UpgradeService", "src/server/Services/UpgradeService.luau"))
    out.append(mod("QuestService", "src/server/Services/QuestService.luau"))
    out += [mod(n, p) for n, p in after_glue]
    out.append(suite(body))
    return "\n".join(out)


def build_persist():
    return persist_suite("persist_body.luau")


def build_persist_cores():
    # Con el SaveService v2 congelado (tests/fixtures) para probar la vuelta atrás.
    return persist_suite("persist_cores_body.luau", [("SaveServiceV2", "tests/fixtures/SaveService_v2.luau")])


def build_core_service():
    # Fase 2 de los núcleos: CoreService real sobre la persistencia real.
    return persist_suite("core_service_body.luau", after_glue=[
        ("CombatConfig", "src/shared/Config/CombatConfig.luau"),
        ("CombatMath", "src/shared/CombatMath.luau"),
        ("AbilityConfig", "src/shared/Config/AbilityConfig.luau"),
        ("AbilityLogic", "src/shared/AbilityLogic.luau"),
        ("CoreService", "src/server/Services/CoreService.luau"),
    ])


def build_rebirth():
    # RebirthService real sobre la persistencia real; PetService simulado (rebirth_glue).
    return persist_suite("rebirth_body.luau", after_glue=[
        ("CombatConfig", "src/shared/Config/CombatConfig.luau"),
        ("CombatMath", "src/shared/CombatMath.luau"),
        ("EggConfig", "src/shared/Config/EggConfig.luau"),
        ("EggLogic", "src/server/Util/EggLogic.luau"),
        ("PetService", "tests/harness/rebirth_glue.luau"),
        ("RebirthService", "src/server/Services/RebirthService.luau"),
    ])


def build_adventure():
    # AdventureService real sobre la persistencia real; posiciones del mundo simuladas.
    return persist_suite("adventure_body.luau", after_glue=[
        ("AdventureService", "src/server/Services/AdventureService.luau"),
    ])


def build_shop():
    # Premios (RewardService) y tienda (ShopService) reales sobre la persistencia real;
    # Roblox (pases y recibos) y PetService simulados (shop_glue, con EggLogic real).
    return persist_suite("shop_body.luau", after_glue=[
        ("EggConfig", "src/shared/Config/EggConfig.luau"),
        ("EggLogic", "src/server/Util/EggLogic.luau"),
        ("AdventureService", "src/server/Services/AdventureService.luau"),
        ("PetService", "tests/harness/shop_glue.luau"),
        ("CodesConfig", "src/server/CodesConfig.luau"),
        ("RewardService", "src/server/Services/RewardService.luau"),
        ("ShopService", "src/server/Services/ShopService.luau"),
        ("GeneratorConfig", "src/shared/Config/GeneratorConfig.luau"),
        ("ChestConfig", "src/shared/Config/ChestConfig.luau"),
        ("ChestService", "src/server/Services/ChestService.luau"),
    ])


def build_quest():
    order = [
        ("EconomyConfig", "src/shared/Config/EconomyConfig.luau"),
        ("Economy", "src/shared/Economy.luau"),
        ("RebirthConfig", "src/shared/Config/RebirthConfig.luau"),
        ("RebirthLogic", "src/shared/RebirthLogic.luau"),
        ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
        ("AdventureLogic", "src/shared/AdventureLogic.luau"),
        ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
        ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
        ("PetCombatConfig", "src/shared/Config/PetCombatConfig.luau"),
        ("PetConfig", "src/shared/Config/PetConfig.luau"),
        ("QuestConfig", "src/shared/Config/QuestConfig.luau"),
        ("Constants", "src/shared/Constants.luau"),
        ("RateLimiter", "src/server/Util/RateLimiter.luau"),
        ("QuestLogic", "src/server/Util/QuestLogic.luau"),
        ("TutorialConfig", "src/shared/Config/TutorialConfig.luau"),
        ("TutorialLogic", "src/server/Util/TutorialLogic.luau"),
        ("GameEvents", "src/server/Util/GameEvents.luau"),
        ("RewardConfig", "src/shared/Config/RewardConfig.luau"),
        ("RewardLogic", "src/server/Util/RewardLogic.luau"),
        ("MonetizationConfig", "src/shared/Config/MonetizationConfig.luau"),
        ("MonetizationLogic", "src/shared/MonetizationLogic.luau"),
        ("LeaderboardLogic", "src/server/Util/LeaderboardLogic.luau"),
    ] + CORE + [
        ("SaveService", "src/server/Services/SaveService.luau"),
    ]
    out = [harness("questtest_stubs.luau"), "services.ReplicatedStorage = { WaitForChild = function() return {} end }\n"]
    for n, p in order:
        out.append(mod(n, p))
        if n == "TutorialLogic":
            out.append("TutorialLogic.init(TutorialConfig)\n")
        if n == "CoreLogic":
            out.append(CORE_INIT)
    out.append(harness("questtest_glue.luau"))
    out.append(mod("QuestService", "src/server/Services/QuestService.luau"))
    out.append(suite("questtest_body.luau"))
    return "\n".join(out)


def build_tutorial():
    return services_suite([harness("persist_stubs.luau")], True, suite("tutorial_body.luau"))


def build_sandbox():
    return services_suite([harness("persist_stubs.luau"), harness("sandbox_pre.luau")], False, suite("sandbox_body.luau"))


def build_sandbox_early():
    return services_suite([harness("persist_stubs.luau"), harness("sandbox_pre.luau")], False, suite("sandbox_early_body.luau"))


def build_sanctuary():
    out = [harness("sanctuary_stubs.luau")]
    for n, p in [
        ("GeneratorConfig", "src/shared/Config/GeneratorConfig.luau"),
        ("WorldConfig", "src/shared/Config/WorldConfig.luau"),
        ("EggConfig", "src/shared/Config/EggConfig.luau"),
        ("PartFactory", "src/server/Util/PartFactory.luau"),
        ("GeneratorService", "src/server/Services/GeneratorService.luau"),
        ("GeneratorAnimator", "src/client/Controllers/GeneratorAnimator.luau"),
    ]:
        out.append(mod(n, p))
    out.append(suite("sanctuary_body.luau"))
    return "\n".join(out)


def build_shrines():
    out = [harness("sanctuary_stubs.luau")]
    for n, p in [
        ("GeneratorConfig", "src/shared/Config/GeneratorConfig.luau"),
        ("WorldConfig", "src/shared/Config/WorldConfig.luau"),
        ("CoreConfig", "src/shared/Config/CoreConfig.luau"),
        ("CoreShrineConfig", "src/shared/Config/CoreShrineConfig.luau"),
        ("EggConfig", "src/shared/Config/EggConfig.luau"),
        ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
        ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
        ("PartFactory", "src/server/Util/PartFactory.luau"),
        ("CoreShrineService", "src/server/Services/CoreShrineService.luau"),
    ]:
        out.append(mod(n, p))
    out.append(suite("shrines_body.luau"))
    return "\n".join(out)


def build_combat():
    enemy_service = read("src", "server", "Services", "EnemyService.luau")
    builders = re.findall(r"^function BUILDERS\.([A-Za-z]+)", enemy_service, re.M)
    shapes_block = re.search(r"^local SHAPES = \{\n(.*?)^\}", enemy_service, re.M | re.S).group(1)
    shapes = re.findall(r"^\s+([A-Za-z]+) = \{", shapes_block, re.M)
    out = [harness("combat_header.luau")]
    for n, p in [
        ("CombatConfig", "src/shared/Config/CombatConfig.luau"),
        ("PetCombatConfig", "src/shared/Config/PetCombatConfig.luau"),
        ("CombatMath", "src/shared/CombatMath.luau"),
        ("EconomyConfig", "src/shared/Config/EconomyConfig.luau"),
        ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
        ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
        ("EnemyLogic", "src/server/Util/EnemyLogic.luau"),
    ]:
        out.append(mod(n, p))
    # Los estilos de modelo que construye el EnemyService real.
    out.append("local BUILDERS = { %s }\n" % ",".join('"%s"' % b for b in builders))
    out.append("local SHAPES = { %s }\n" % ",".join('"%s"' % s for s in shapes))
    out.append(suite("combattest_body.luau"))
    return "\n".join(out)


PET_COMBAT_REQUIRES = [
    'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
    'local Shared = ReplicatedStorage:WaitForChild("Shared")',
    "local Constants = require(Shared.Constants)",
    "local CombatConfig = require(Shared.Config.CombatConfig)",
    "local PetCombatConfig = require(Shared.Config.PetCombatConfig)",
    "local CombatMath = require(Shared.CombatMath)",
    "local RebirthLogic = require(Shared.RebirthLogic)",
    "local AdventureLogic = require(Shared.AdventureLogic)",
    "local PlayerDataService = require(script.Parent.PlayerDataService)",
    "local RemoteService = require(script.Parent.RemoteService)",
    "local EnemyService = require(script.Parent.EnemyService)",
    "local CombatService = require(script.Parent.CombatService)",
]


def build_petcombat():
    out = [harness("petcombat_stubs.luau")]
    for n, p in [
        ("Constants", "src/shared/Constants.luau"),
        ("CombatConfig", "src/shared/Config/CombatConfig.luau"),
        ("PetCombatConfig", "src/shared/Config/PetCombatConfig.luau"),
        ("CombatMath", "src/shared/CombatMath.luau"),
        ("EconomyConfig", "src/shared/Config/EconomyConfig.luau"),
        ("RebirthConfig", "src/shared/Config/RebirthConfig.luau"),
        ("RebirthLogic", "src/shared/RebirthLogic.luau"),
        ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
        ("AdventureLogic", "src/shared/AdventureLogic.luau"),
        ("EnemyLogic", "src/server/Util/EnemyLogic.luau"),
    ]:
        out.append(mod(n, p))
    # PetCombatService real, con sus dependencias de servicio sustituidas por las simuladas.
    source = read("src", "server", "Services", "PetCombatService.luau")
    for line in PET_COMBAT_REQUIRES:
        assert line in source, line
        source = source.replace(line + "\n", "")
    out.append(suite("petcombat_body.luau").replace("PETCOMBAT_SOURCE_HERE", source))
    return "\n".join(out)


def build_abilities():
    # AbilityService real con EnemyLogic, CoreLogic, CombatMath y AbilityLogic reales.
    out = [harness("abilities_stubs.luau")]
    for n, p in [
        ("Constants", "src/shared/Constants.luau"),
        ("EconomyConfig", "src/shared/Config/EconomyConfig.luau"),
        ("Economy", "src/shared/Economy.luau"),
        ("CombatConfig", "src/shared/Config/CombatConfig.luau"),
        ("PetCombatConfig", "src/shared/Config/PetCombatConfig.luau"),
        ("CombatMath", "src/shared/CombatMath.luau"),
        ("CoreConfig", "src/shared/Config/CoreConfig.luau"),
        ("CoreLogic", "src/server/Util/CoreLogic.luau"),
        ("AbilityConfig", "src/shared/Config/AbilityConfig.luau"),
        ("AbilityLogic", "src/shared/AbilityLogic.luau"),
        ("RebirthConfig", "src/shared/Config/RebirthConfig.luau"),
        ("RebirthLogic", "src/shared/RebirthLogic.luau"),
        ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
        ("AdventureLogic", "src/shared/AdventureLogic.luau"),
        ("EnemyLogic", "src/server/Util/EnemyLogic.luau"),
        ("RateLimiter", "src/server/Util/RateLimiter.luau"),
    ]:
        out.append(mod(n, p))
        if n == "CoreLogic":
            out.append(CORE_INIT)
    out.append(harness("abilities_enemies.luau"))
    out.append(mod("AbilityService", "src/server/Services/AbilityService.luau"))
    out.append(suite("abilities_body.luau"))
    return "\n".join(out)


def build_landscape():
    # Distribución del paisaje (pura) con las configuraciones reales de todas las zonas.
    out = [harness("landscape_stubs.luau")]
    for n, p in [
        ("LandscapeConfig", "src/shared/Config/LandscapeConfig.luau"),
        ("WorldConfig", "src/shared/Config/WorldConfig.luau"),
        ("ValleyConfig", "src/shared/Config/ValleyConfig.luau"),
        ("CalderaConfig", "src/shared/Config/CalderaConfig.luau"),
        ("CoreShrineConfig", "src/shared/Config/CoreShrineConfig.luau"),
        ("EggConfig", "src/shared/Config/EggConfig.luau"),
        ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
        ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
        ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
        ("VillageConfig", "src/shared/Config/VillageConfig.luau"),
        ("WildsConfig", "src/shared/Config/WildsConfig.luau"),
        ("ChestConfig", "src/shared/Config/ChestConfig.luau"),
        ("LandscapeLayout", "src/server/Util/LandscapeLayout.luau"),
    ]:
        out.append(mod(n, p))
    out.append(suite("landscape_body.luau"))
    return "\n".join(out)


def build_anim():
    source = read("src", "client", "Controllers", "EnemyAnimator.luau")
    return harness("animtest_stubs.luau") + "\n" + suite("animtest_body.luau").replace("ANIMATOR_SOURCE_HERE", source)


def build_pose():
    source = read("src", "server", "Services", "EnemyService.luau")
    function_text = source[source.index("local ARM_PARTS"):source.index("local function addJoints")]
    names = set()
    for match in re.finditer(r'(?:box|orb|limb|piece|eye|crystalSpike)\(rig, "(\w+)"( \.\. (side|index|side \.\. forward))?', source):
        base, suffix = match.group(1), match.group(3)
        if suffix is None:
            names.add(base)
        elif suffix == "side":
            names.update([base + "-1", base + "1"])
        elif suffix == "index":
            names.update([base + str(i) for i in range(1, 7)])
        else:
            names.update([base + a + b for a in ("-1", "1") for b in ("-1", "1")])
    names_line = "\nlocal names = {" + ",".join('"%s"' % n for n in sorted(names)) + "}\n"
    return function_text + names_line + suite("pose_body.luau")


def build_cores():
    # Lógica pura: sin entorno simulado; solo los módulos reales y sus dependencias.
    out = [mod(n, p) for n, p in [
        ("EconomyConfig", "src/shared/Config/EconomyConfig.luau"),
        ("Economy", "src/shared/Economy.luau"),
        ("CoreConfig", "src/shared/Config/CoreConfig.luau"),
        ("CoreLogic", "src/server/Util/CoreLogic.luau"),
    ]]
    out.append(suite("cores_body.luau"))
    return "\n".join(out)


def build_zones():
    # Zonas: ZoneLogic (desbloqueo con renacimientos) y coherencia de todas las
    # configuraciones que dependen de las zonas (enemigos, huevos, aventuras, misiones).
    out = [harness("zones_stubs.luau")]
    out += [mod(n, p) for n, p in [
        ("Constants", "src/shared/Constants.luau"),
        ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
        ("ZoneLogic", "src/server/Util/ZoneLogic.luau"),
        ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
        ("PetConfig", "src/shared/Config/PetConfig.luau"),
        ("EggConfig", "src/shared/Config/EggConfig.luau"),
        ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
        ("QuestConfig", "src/shared/Config/QuestConfig.luau"),
        ("LandscapeConfig", "src/shared/Config/LandscapeConfig.luau"),
        ("CalderaConfig", "src/shared/Config/CalderaConfig.luau"),
        ("PortalDesign", "src/server/Util/PortalDesign.luau"),
    ]]
    out.append(suite("zones_body.luau"))
    return "\n".join(out)


def build_leaderboard():
    # Clasificación (pura) y sitio de los monolitos en el bosque (con el paisaje real).
    out = [harness("landscape_stubs.luau")]
    for n, p in [
        ("LandscapeConfig", "src/shared/Config/LandscapeConfig.luau"),
        ("WorldConfig", "src/shared/Config/WorldConfig.luau"),
        ("ValleyConfig", "src/shared/Config/ValleyConfig.luau"),
        ("CalderaConfig", "src/shared/Config/CalderaConfig.luau"),
        ("CoreShrineConfig", "src/shared/Config/CoreShrineConfig.luau"),
        ("EggConfig", "src/shared/Config/EggConfig.luau"),
        ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
        ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
        ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
        ("VillageConfig", "src/shared/Config/VillageConfig.luau"),
        ("WildsConfig", "src/shared/Config/WildsConfig.luau"),
        ("ChestConfig", "src/shared/Config/ChestConfig.luau"),
        ("LandscapeLayout", "src/server/Util/LandscapeLayout.luau"),
        ("LeaderboardConfig", "src/shared/Config/LeaderboardConfig.luau"),
        ("LeaderboardLogic", "src/server/Util/LeaderboardLogic.luau"),
    ]:
        out.append(mod(n, p))
    out.append(suite("leaderboard_body.luau"))
    return "\n".join(out)


def build_world():
    # Mundo vivo (puro): ciclo de día y noche, cofres escondidos (lógica y configuración)
    # y cauce del río.
    out = [harness("world_stubs.luau")]
    for n, p in [
        ("WorldConfig", "src/shared/Config/WorldConfig.luau"),
        ("DayNight", "src/shared/DayNight.luau"),
        ("RewardConfig", "src/shared/Config/RewardConfig.luau"),
        ("RewardLogic", "src/server/Util/RewardLogic.luau"),
        ("AdventureConfig", "src/shared/Config/AdventureConfig.luau"),
        ("ChestConfig", "src/shared/Config/ChestConfig.luau"),
        ("WildsConfig", "src/shared/Config/WildsConfig.luau"),
    ]:
        out.append(mod(n, p))
    out.append(suite("world_body.luau"))
    return "\n".join(out)


def build_weapons():
    # Armas (WeaponConfig + WeaponLogic, puras) con los enemigos y zonas reales.
    out = [harness("combat_header.luau")]
    for n, p in [
        ("CombatConfig", "src/shared/Config/CombatConfig.luau"),
        ("WeaponConfig", "src/shared/Config/WeaponConfig.luau"),
        ("WeaponLogic", "src/shared/WeaponLogic.luau"),
        ("EnemyConfig", "src/shared/Config/EnemyConfig.luau"),
        ("ZoneConfig", "src/shared/Config/ZoneConfig.luau"),
    ]:
        out.append(mod(n, p))
    out.append(suite("weapons_body.luau"))
    return "\n".join(out)


def build_hudlayout():
    # Diseño del HUD del cliente (cálculo puro): Vector2 mínimo simulado.
    stub = "local Vector2 = { new = function(x, y) return { X = x, Y = y } end }\n"
    return stub + mod("HudLayout", "src/client/UI/HudLayout.luau") + suite("hudlayout_body.luau")


SUITES = [
    ("sanctuary", "Santuario del Núcleo Cósmico (geometría y animación)", build_sanctuary),
    ("shrines", "Círculo Elemental: altares de los núcleos (contrato y mapa)", build_shrines),
    ("sandbox", "Modo prueba del tutorial", build_sandbox),
    ("sandbox_early", "Modo prueba con el jugador antes del arranque", build_sandbox_early),
    ("tutorial", "Tutorial inicial", build_tutorial),
    ("persist", "Persistencia de energía y mejoras", build_persist),
    ("persist_cores", "Persistencia v3: núcleos, migración y vuelta atrás", build_persist_cores),
    ("quest", "Misiones, diarias y logros", build_quest),
    ("combat", "Combate (daño, muertes, recompensas, objetivos)", build_combat),
    ("weapons", "Armas: comprar, mejorar, equipar, daño y guardado", build_weapons),
    ("petcombat", "Combate de mascotas", build_petcombat),
    ("anim", "Animación de enemigos", build_anim),
    ("pose", "Articulaciones de los enemigos", build_pose),
    ("cores", "Ocho núcleos: configuración y lógica pura", build_cores),
    ("core_service", "Núcleos fase 2: despertar, mejorar, elegir y producción offline", build_core_service),
    ("abilities", "Habilidades elementales (fórmulas, estados y servicio)", build_abilities),
    ("landscape", "Paisaje: caminos, bosque, puntos de referencia y límites", build_landscape),
    ("rebirth", "Renacimiento: requisito, reinicio, fichas, tienda y multiplicadores", build_rebirth),
    ("adventure", "Aventuras: personajes, misiones, amuletos y bendiciones", build_adventure),
    ("zones", "Zonas: desbloqueo con renacimientos y coherencia de la Caldera", build_zones),
    ("leaderboard", "Monolitos de clasificación: orden y sitio junto al spawn", build_leaderboard),
    ("shop", "Premio diario, códigos, pases, compras sueltas y mejora automática", build_shop),
    ("hudlayout", "Interfaz: menú, avisos y columnas sin solaparse en muchas pantallas", build_hudlayout),
    ("world", "Mundo vivo: día y noche, cofres escondidos y río", build_world),
]
LEGACY = ["pettest", "eggtest", "zonetest", "savetest", "layouttest", "stagetest"]


def luau_binary():
    folder = os.environ.get("LUAU_BIN") or os.path.join(ROOT, "tools", "luau")
    for name in ("luau.exe", "luau"):
        candidate = os.path.join(folder, name)
        if os.path.isfile(candidate):
            return candidate
    sys.exit(f"No se encuentra el intérprete de Luau en {folder}. Define LUAU_BIN o copia luau.exe a tools/luau/.")


def run(binary, path):
    result = subprocess.run([binary, path], capture_output=True, text=True, encoding="utf-8", errors="replace")
    output = (result.stdout + result.stderr).strip().splitlines()
    ok_count = sum(1 for line in output if line.startswith("OK"))
    last = output[-1] if output else "(sin salida)"
    passed = result.returncode == 0 and last.strip() == "TODO OK"
    return passed, ok_count, last, output


def warn_sandbox():
    config = read("src", "server", "DevConfig.luau")
    if re.search(r"^\s*TutorialSandbox\s*=\s*true", config, re.M):
        print("AVISO: src/server/DevConfig.luau tiene TutorialSandbox = true. Déjalo en false antes de hacer commit.\n")


def main(arguments):
    # La consola de Windows no usa UTF-8 por defecto: así se ven bien los acentos.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    include_legacy = "--legacy" in arguments
    selected = [a for a in arguments if not a.startswith("--")]
    binary = luau_binary()
    os.makedirs(BUILD, exist_ok=True)
    warn_sandbox()

    failures = 0
    print("Baterías actuales (montadas desde src/):")
    for key, title, builder in SUITES:
        if selected and key not in selected:
            continue
        path = os.path.join(BUILD, key + ".luau")
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(check_no_require(builder()))
        passed, ok_count, last, output = run(binary, path)
        failures += 0 if passed else 1
        detail = f"{ok_count:>3} comprobaciones" if ok_count else "resumen: " + (output[-2] if len(output) > 1 else last)
        print(f"  {'PASA ' if passed else 'FALLA'}  {key:<14} {detail}  · {title}")
        if not passed:
            for line in output[-15:]:
                print("         " + line)

    if include_legacy:
        print("\nBaterías HEREDADAS (copias antiguas de módulos dentro: NO validan el código actual):")
        for name in LEGACY:
            passed, ok_count, last, _ = run(binary, os.path.join(TESTS, "legacy", name + ".luau"))
            print(f"  {'pasa ' if passed else 'falla'}  {name:<14} {ok_count:>3} comprobaciones  · referencia histórica")

    print("\nResultado:", "TODO CORRECTO" if failures == 0 else f"{failures} batería(s) con fallos")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
