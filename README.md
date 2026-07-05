# Turtle-Flotte v5 fuer CC:Tweaked / ComputerCraft

v5 baut die Flotte generisch auf:

- 1 Koordinator
- n Arbeiter, n >= 1
- 1 Taschencomputer fuer Befehle

Arbeiter haben keine fest verdrahteten Rollenskripte mehr. Jeder Arbeiter startet `worker.lua`, erkennt seine Turtle-Upgrades und meldet daraus seinen Beruf.

Wichtig: Mit den zwei Slots des Arbeiters sind die Turtle-Upgrade-Slots gemeint, nicht Inventarslots. Jeder Arbeiter braucht ein Modem-Upgrade und ein Werkzeug-/Funktions-Upgrade.

## Architektur

Die Hauptprogramme sind duenn:

- `Skripte/koordinator.lua` startet Rednet, `coordinator_brain.lua` und die Loops.
- `Skripte/worker.lua` startet `worker_runtime.lua`.
- Alte Starter wie `worker_bergbau.lua` bleiben kompatibel, geben eine Deprecated-Warnung aus und starten intern `worker.lua`.
- `Skripte/flotte.lua` ist die Taschencomputer-CLI.

Neue Standardbibliotheken:

- `vec3.lua`, `direction.lua`: Koordinaten und Richtungsmathematik.
- `equipment.lua`: liest ausgeruestete Turtle-Upgrades.
- `inventory.lua`: Fuel, Slots und Itemzaehlung.
- `task_queue.lua`: FIFO-TODO-Listen fuer Befehle und Worker-Aufgaben.
- `protocol.lua`: zentrale Rednet-Nachrichten.
- `nav2.lua`: Navigation ohne automatisches Graben.
- `safety.lua`: Sicherheitslogik gegen Herunterfallen.
- `terrain.lua`: Terrainmodell und Abbauplanung.
- `report.lua`: chronologische Reports mit Saldo.
- `worker_runtime.lua`: universeller Worker.
- `coordinator_brain.lua`: Koordinator-Planer.

## Berufserkennung

`equipment.lua` nutzt, falls vorhanden:

- `turtle.getEquippedLeft()`
- `turtle.getEquippedRight()`

Falls die API in der Laufzeit fehlt, startet der Worker trotzdem. Der Beruf ist dann `unbekannt` und der Status enthaelt eine Warnung.

Erkennung:

- Upgrade-Name enthaelt `shovel` -> `graben`
- Upgrade-Name enthaelt `pickaxe` -> `bergbau`
- Upgrade-Name enthaelt `craft`, `crafting`, `workbench` oder `crafty` -> `handwerk`
- Upgrade-Name enthaelt `axe`, aber nicht `pickaxe` -> `holzfaeller`
- sonst -> `unbekannt`

Der Koordinator ist verantwortlich, `aktion=true` nur an einen Arbeiter mit passendem Beruf zu senden. Der Arbeiter prueft nur, ob `requiredProfession` zu seinem Beruf passt.

## Worker-TODO-Liste

Jeder Worker haelt eine eigene FIFO-TODO-Liste. Der wichtigste Task ist `move_action`:

```lua
{
  wohin = { x = 10, y = 64, z = 20 },
  aktion = false,
  requiredProfession = nil,
  requireSupport = true,
}
```

Semantik:

- `aktion=false`: Worker laeuft exakt zu `wohin`, ohne zu graben.
- `aktion=true`: Worker laeuft neben `wohin`, schaut zum Zielblock und baut ihn ab.
- Bei falschem Beruf meldet der Worker `worker_task_failed` mit `wrong_profession`.
- Bei Blockade meldet der Worker `worker_blocked` mit `pos`, `blockedPos` und `block`.
- Bei Fuel `< 5` meldet der Worker `worker_need_fuel` und stoppt sicher.
- Bei vollem Inventar meldet der Worker `worker_inventory_full` und stoppt sicher.

`nav2.lua` graebt nie automatisch. Graben passiert nur bei expliziten Aktions-Tasks.

## Koordinator-Queues

Der Koordinator-Brain haelt:

- `commandQueue`: Pocket-Befehle.
- `subtaskQueue`: konkrete Worker- oder Service-Aufgaben.
- `terrain`: bekannte Bloecke, Luft, Blockaden und Support.
- `reports`: chronologische Reports.

Prioritaeten:

1. `worker_need_fuel`
2. `worker_inventory_full`
3. `worker_blocked`
4. laufende Scan-/Abbau-Subtasks
5. neue Pocket-Commands
6. Standby

Blockaden werden im Terrainmodell gespeichert. Aus dem Blocknamen bestimmt der Koordinator den passenden Beruf und schickt einen passenden Worker mit `move_action` und `aktion=true`.

## Abbau

Pocket-Befehl:

```text
flotte abbau 100,64,200 90,67,190 110,80,210
flotte abbau lager 100,64,200 von 90,67,190 bis 110,80,210
```

Ablauf:

1. Befehl wird in die `commandQueue` eingetragen.
2. Report startet.
3. Bereich wird normalisiert.
4. Highest-Point-Search wird als Subtasks geplant.
5. Wenn der hoechste Punkt bekannt ist, plant der Koordinator Y-Schichten von `highest.y` bis `area.minY`.
6. Jede Schicht wird von aussen nach innen geplant.
7. Aussenpositionen werden nur mit `requireSupport=true` genutzt, damit Worker nicht blind nach aussen laufen und herunterfallen.
8. Blockaden werden als Terraininformation genutzt und mit passendem Worker bearbeitet.
9. Wenn alle Subtasks fertig sind, wird der Report gespeichert.

## Standby

Wenn keine Pocket-Befehle und keine Subtasks offen sind, plant der Koordinator Standby:

- Worker zur Init-Truhe zurueckrufen.
- Worker einzeln abbauen.
- Worker in die Init-Truhe legen.
- Lose Items in Lager/Init-Truhe sortieren.
- Koordinator an/auf die Init-Truhe bewegen.
- Status wird `standby`.

Falls ein Worker nicht erreichbar ist, wird eine Warnung/Report-Ereignis erzeugt. Es wird nicht endlos gewartet.

## Installation

Repository-URL:

```text
https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

Koordinator:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init koordinator bergwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

Worker:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init worker bergwerk_01 worker_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

Alte Rollen bleiben Alias fuer Worker:

```text
init bergbau bergwerk_01 worker_bergbau_01 basis_01
init graben bergwerk_01 worker_graben_01 basis_01
init holzfaeller bergwerk_01 worker_holz_01 basis_01
init handwerk bergwerk_01 worker_handwerk_01 basis_01
```

Taschencomputer:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init_flotte.lua
init_flotte pocket bergwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

## Config-Minimierung

Pflicht:

- `group`

Optional:

- `id`, sonst `os.getComputerID()`
- `coordinator` beim Worker
- `initChest`, wenn der Koordinator sie nicht automatisch/zuverlaessig bestimmen kann
- `protocolPrefix`
- `start` und `facing`, falls GPS/Facing-Kalibrierung nicht reicht

Automatisch ermittelt, soweit die Laufzeit es hergibt:

- Worker-Beruf aus Turtle-Upgrades
- Position per GPS
- Facing per GPS-Bewegung
- Worker-Discovery ueber `worker_hello`
- Modem ueber Peripheral-/Rednet-Erkennung

## Taschencomputer-Befehle

```text
flotte list
flotte status
flotte abbau <lager:x,y,z> <von:x,y,z> <bis:x,y,z>
flotte abbau lager <lager:x,y,z> von <von:x,y,z> bis <bis:x,y,z>
flotte stop
flotte standby
```

`flotte status` zeigt:

- Koordinatorstatus
- `commandQueue`
- `subtaskQueue`
- aktueller Befehl
- aktueller Report
- Worker mit `id`, `profession`, Fuel, freien Slots, Position, Facing, Equipment und aktuellem Task

## Reports

Reports liegen standardmaessig unter `berichte/`.

Sie enthalten:

- chronologische Events
- Command-Payload
- Status
- Saldo mit Fuel, Items, Worker-Tasks und Fehleranzahl
