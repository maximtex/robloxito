-- Opciones de desarrollo (solo servidor: el cliente no puede leerlas ni cambiarlas).
--
-- TutorialSandbox = true: en Roblox Studio, cada Play empieza como un jugador NUEVO, con
-- un perfil temporal en memoria. El perfil real NO se lee, NO se bloquea y NO se guarda
-- (no se llama a SaveService.load ni a SaveService.save). Se ve un aviso en pantalla.
-- En una partida publicada se IGNORA siempre (RunService:IsStudio() es false), aunque se
-- haya quedado en true por descuido; el servidor lo avisa en la consola.
--
-- SandboxStartingMoney: 💰 inicial del perfil temporal, para no esperar a juntar el dinero
-- de los huevos y del portal del Valle (los 💎 empiezan en 0, como un jugador nuevo).
--
-- En el repositorio se guarda SIEMPRE con TutorialSandbox = false. Para probar en local:
-- cámbialo a true (Rojo lo sincroniza), pulsa Play en Studio y vuelve a dejarlo en false
-- antes de hacer commit. `python tests/run_tests.py` avisa si se ha quedado en true.
--
-- StudioPasses = true: en Studio, el jugador tiene todos los pases de la tienda (Diamantes ×2,
-- Mejora automática, Abrir ×3, Más mascotas, Disparo automático) sin comprarlos, para
-- probarlos. Fuera de Studio se ignora. En el repositorio, false.

return {
	TutorialSandbox = false,
	SandboxStartingMoney = 15000,
	StudioPasses = false,
}
