-- Armería (panel "Armory") con el diseño «Armería Roblox»: cabecera naranja a rayas con
-- ARMERÍA (o GUANTES / BASTONES: cada estilo de pelea tiene su tienda y solo se ve la de tu
-- estilo, WeaponConfig.Category), los botones ⚡ MEJORAS (habilidades del estilo,
-- SkillsController) y 🎭 CLASES (ClassesController), el dinero y la X roja; debajo, una tarjeta por arma (cuatro a la vista; las
-- flechas pasan al resto) con su arte, su rareza, sus números y sus botones: comprar con
-- dinero o con Robux, equipar y mejorar. Se abre en el puesto del pueblo, con la tecla L o
-- con el botón "Armas" del menú. Solo muestra y pide: el servidor valida y cobra
-- (WeaponService; las compras con Robux, ShopService).
-- Datos de los atributos del jugador: Weapons ("Laser:3,PlasmaBlaster:0"), EquippedWeapon,
-- Money, UnlockedZones, PetMultiplier y UpgradeLevel_LaserSpeed (cadencia).

--
-- Dividido en partes (Fase 3 del rediseño; mismo comportamiento): Helpers, CardGui, WindowGui, Startup.
-- Cada parte se registra en la tabla de estado (install) y luego toma lo de las demás
-- (link); sus funciones públicas se copian aquí, a WeaponController, con el mismo nombre.

local WeaponController = {}

local PARTS = {
	require(script.Helpers),
	require(script.CardGui),
	require(script.WindowGui),
	require(script.Startup),
}

-- Estado compartido entre las partes (lo que antes eran variables de primer nivel).
local ctx: any = {
	Service = WeaponController,
}

for _, part in PARTS do
	part.install(ctx)
end
for _, part in PARTS do
	part.link(ctx)
end
for _, part in PARTS do
	for name, fn in part.Api do
		assert(WeaponController[name] == nil, "función pública repetida: " .. name)
		WeaponController[name] = fn
	end
end

return WeaponController
