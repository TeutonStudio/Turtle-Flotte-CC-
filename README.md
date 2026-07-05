# Turtle-Flotte fuer CC:Tweaked / ComputerCraft

Diese Anleitung beschreibt die Einrichtung einer Flotte aus:

- einem Taschencomputer fuer Befehle,
- einer Koordinator-Turtle mit Endermodem und Chatty/Chatbox,
- vier Worker-Turtles mit Endermodem und Werkzeug.

Im Repository liegt im Root nur `init.lua`. Die restlichen Dateien sind sortiert:

- `Bibliothek/`: gemeinsame Lua-Module.
- `Config/`: Beispiel-Configs.
- `Skripte/`: Programme, Startup-Dateien und Dokumentation.

`init.lua` wird per `wget` auf jeden Computer geladen. Danach laedt es die benoetigten Dateien aus `Bibliothek/` und `Skripte/` nach und speichert sie auf dem ComputerCraft-Rechner flach als `fleet_common.lua`, `koordinator.lua`, `flotte.lua` usw.

## GitHub-URL

Die folgenden Befehle verwenden dieses Repository:

```text
https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

## Taschencomputer Einrichten

Der Taschencomputer braucht ein Endermodem/Wireless Modem und die Pocket-Steuerung `flotte`.

Auf dem Taschencomputer ausfuehren:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init_flotte.lua
init_flotte pocket bergwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

Bedeutung:

- `bergwerk_01`: Gruppenname der Flotte.
- `basis_01`: ID des Koordinators.

Danach steht der Befehl `flotte` zur Verfuegung.

## Koordinator Einrichten

Der Koordinator ist eine Turtle, die vor der Init-/Personal-Truhe steht und in Richtung dieser Truhe schaut.

Der Koordinator braucht:

- Endermodem/Wireless Modem fuer Rednet.
- Chatty/Chatbox-Peripheral fuer Meldungen im Chat.
- Treibstoff in der Init-Truhe.
- Worker-Turtles in der Init-Truhe.

Auf dem Koordinator ausfuehren:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init koordinator bergwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

Danach `fleet_config.lua` auf dem Koordinator pruefen und ausfuellen:

```lua
start = { x = 789, y = 64, z = -967 }
facing = "north"
initChest = { x = 789, y = 64, z = -968 }
chestSide = "front"
```

Wichtig:

- `start` ist die GPS-Startposition des Koordinators.
- `facing` ist die Blickrichtung beim Start.
- `initChest` ist die Koordinate der Init-/Personal-Truhe.
- `chestSide` ist die Seite, auf der die Truhe beim Start steht, normalerweise `front`.

Ohne `initChest` kann der Koordinator Worker deployen, aber nach Servicefahrten nicht sicher zur Ursprungstruhe zurueckkehren.

Der Koordinator gibt jedem Worker beim Deploy einen Stack Treibstoff. Wenn in der Init-Truhe weniger als `(Arbeiter + 1) * 64` Treibstoff-Puffer uebrig ist, meldet er das im Chat. Wenn kein Treibstoff mehr gezogen werden kann, meldet er das ebenfalls.

## Worker Einrichten

Jeder Worker braucht:

- Endermodem/Wireless Modem fuer Rednet.
- Ein passendes Werkzeug.
- Eine eindeutige ID.
- Dieselbe Gruppe wie der Koordinator.
- Die Koordinator-ID.

Worker melden nach dem Platzieren ihre Rolle per Rednet. Dadurch koennen mehrere Worker derselben Kategorie genutzt werden.

### Bergbau-Worker

Fuer harte Bloecke, Stein, Erze, Deepslate usw.

Benötigt:

- Mining Turtle oder Turtle mit Spitzhacke.
- Endermodem.

Auf der Bergbau-Turtle ausfuehren:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init bergbau bergwerk_01 bergbau_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

### Graben-Worker

Fuer weiche Bloecke wie Erde, Sand, Kies, Lehm, Schnee.

Benötigt:

- Turtle mit Schaufel.
- Endermodem.

Auf der Graben-Turtle ausfuehren:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init graben bergwerk_01 graben_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

### Handwerk-Worker

Fuer Crafting-Auftraege.

Benötigt:

- Crafty Turtle/Crafting Turtle.
- Endermodem.
- Zutaten im Inventar der Handwerks-Turtle.

Auf der Handwerks-Turtle ausfuehren:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init handwerk bergwerk_01 handwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

### Holzfaeller-Worker

Fuer Baeume, Staemme, Holz und Blaetter.

Benötigt:

- Turtle mit Axt.
- Endermodem.

Auf der Holzfaeller-Turtle ausfuehren:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/init.lua init.lua
init holzfaeller bergwerk_01 holz_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master
```

## Starten

Nach der Einrichtung starten Koordinator und Worker ueber `startup.lua` automatisch.

Manuell starten:

```text
koordinator
```

oder auf Workern:

```text
worker_bergbau
worker_graben
worker_handwerk
worker_holzfaeller
```

## Taschencomputer-Befehle

Alle Befehle laufen auf dem Taschencomputer.

### Koordinatoren Suchen

```text
flotte list
```

Zeigt erreichbare Koordinatoren in der konfigurierten Gruppe.

### Status Anzeigen

```text
flotte status
```

Zeigt Koordinator, aktuelle Bericht-ID, Job-Truhe, Service-Warteschlange und bekannte Worker.

### Worker Deployen

```text
flotte deploy all
```

Deployt Worker aus der Init-Truhe und gibt jedem Worker einen Stack Treibstoff.

```text
flotte deploy bergbau
flotte deploy graben
flotte deploy handwerk
flotte deploy holzfaeller
```

Deployt Worker, bis mindestens ein Worker der gewuenschten Rolle online ist.

### Abbau Starten

```text
flotte abbau 100,64,200 90,67,190 110,80,210
```

Format:

```text
flotte abbau <job-truhe:x,y,z> <punkt1:x,y,z> <punkt2:x,y,z>
```

Der Koordinator zerlegt den Bereich in Y-Schichten von oben nach unten und vergibt Schichten an freie Bergbau-Worker. Worker bleiben bei vollem Inventar oder Treibstoffbedarf am Arbeitsplatz. Der Koordinator arbeitet die Service-Warteschlange ab, bringt Treibstoff und transportiert Items zur Job-Truhe.

### Job-Truhe Wechseln

```text
flotte lager_wechsel 105,64,205
```

Aendert die Job-Truhe des aktuell koordinierten Auftrags. Der Bericht enthaelt danach:

```text
Lager Truhenaenderungsdiktat von <alt> nach <neu>
```

### Crafting Starten

```text
flotte craft minecraft:diamond_pickaxe 1
```

Format:

```text
flotte craft <rezept> [anzahl]
```

Die Handwerks-Turtle craftet aus ihrem eigenen Inventar.

### Rollen-Job Starten

```text
flotte job graben graben 100,64,200 90,67,190 110,80,210
```

Format:

```text
flotte job <rolle> <kind> <job-truhe:x,y,z> <punkt1:x,y,z> <punkt2:x,y,z>
```

Gedacht fuer direkte Rollenauftraege, z. B. Graben oder Holzfaellen.

### Stop

```text
flotte stop
```

Sendet einen Abbruch an bekannte Worker.

### Gruppe Oder Koordinator Ueberschreiben

```text
flotte --gruppe bergwerk_02 --basis basis_02 status
```

Ueberschreibt Gruppe und Koordinator-ID nur fuer diesen Befehl.

## Berichte

Der Koordinator schreibt JSON-Berichte:

- `berichte/<request_id>.json`
- `berichte/index.json`

Berichte enthalten Auftrag, Lagertruhe, Worker, Fortschritt, Service-Anfragen, Treibstofflieferungen, Itemtransporte, Lagerwechsel, Fehler und Abschluss.

## Verhalten Bei Hindernissen

Der Koordinator baut bei normalen Servicefahrten keine Bloecke ab. Beim Initialisieren darf er nur die blockierte Deploy-Seite mit `turtle.dig()` freiraeumen. Wenn das nicht klappt, meldet er den stoerenden Block im Chat und im Bericht.
