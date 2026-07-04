# Turtle-Flotte Kurzstart

Die vollstaendige Anleitung steht in `Skripte/README.md`.

Diese Befehle verwenden das Repository `TeutonStudio/Turtle-Flotte-CC-`.

## Taschencomputer

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main/init.lua init
init pocket bergwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main
```

## Koordinator

Koordinator-Turtle mit Endermodem und Chatty/Chatbox vor die Init-Truhe stellen.

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main/init.lua init
init koordinator bergwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main
```

Danach in `fleet_config.lua` `start`, `facing` und `initChest` setzen.

## Arbeiter

Bergbau:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main/init.lua init
init bergbau bergwerk_01 bergbau_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main
```

Graben:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main/init.lua init
init graben bergwerk_01 graben_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main
```

Handwerk:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main/init.lua init
init handwerk bergwerk_01 handwerk_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main
```

Holzfaeller:

```text
wget https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main/init.lua init
init holzfaeller bergwerk_01 holz_01 basis_01 https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/main
```

## Taschencomputer-Befehle

- `flotte list`
- `flotte status`
- `flotte deploy all`
- `flotte deploy <rolle>`
- `flotte abbau <job-truhe:x,y,z> <punkt1:x,y,z> <punkt2:x,y,z>`
- `flotte lager_wechsel <job-truhe:x,y,z>`
- `flotte craft <rezept> [anzahl]`
- `flotte job <rolle> <kind> <job-truhe:x,y,z> <punkt1:x,y,z> <punkt2:x,y,z>`
- `flotte stop`
