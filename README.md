# Flotte

Flotte ist ein v1-Repository fuer ein Multi-Turtle-Wirtschaftssystem in CC: Tweaked. Es trennt drei Rollen:

- Taschencomputer: Spieler-CLI und Rednet-Befehle.
- Koordinator: sequentielle Job-Queue, Worker-Registry, Berichte, Treibstoff- und Lagerlogik.
- Arbeiter: reine Ausfuehrung von Subtasks mit Problem-Meldungen fuer Treibstoff und volles Inventar.

## Voraussetzungen

- Minecraft mit CC: Tweaked.
- Funktionierende GPS-Infrastruktur.
- HTTP API aktiviert und der Raw-Host des Repositories gewhitelistet.
- Rednet-faehiges Ender-/Wireless-Modem an Taschencomputer, Koordinator und Arbeitern.
- Koordinator optional als Turtle, wenn Auspacken/Einpacken und Lagerlogik physisch ausgefuehrt werden sollen.
- Mekanism Personal Chest direkt hinter dem Koordinator, gemaess fester Referenzausrichtung.
- Arbeiter-Turtles mit genau einem passenden Werkzeug: Schaufel, Spitzhacke, Axt oder Crafting/Werkbank-Turtle.

## Installation in CC:Tweaked

Beispiel fuer einen frischen Computer, nachdem die URL in `init.lua` korrekt gehostet ist:

```lua
wget https://github.com/TeutonStudio/Turtle-Flotte-CC-/init.lua init.lua
pastebin get <dein-init-pastebin-code> init.lua
init.lua
```

Alternativ kannst du `init.lua` manuell anlegen, den Inhalt einfuegen und ausfuehren.

## Erster Testlauf

1. Starte den Koordinator und notiere seine Computer-ID.
2. Stelle sicher, dass der Koordinator Rednet offen hat und GPS funktioniert.
3. Starte mindestens eine Arbeiter-Turtle mit Modem und Werkzeug.
4. Starte den Taschencomputer.
5. Suche Koordinatoren:

```text
flotte list
```

6. Lege einen kleinen Abbau-Job an:

```text
flotte abbau id:12 lager:100,64,100 von:105,64,105 bis:107,62,107
```

`id:12` ist durch die echte Koordinator-ID zu ersetzen. `lager`, `von` und `bis` sind GPS-Koordinaten im Format `x,y,z`.

7. Status und Bericht abfragen:

```text
flotte status id:12
flotte bericht id:12-1751800000000
flotte bericht id:12-1751800000000 --voll
```

Die Job-ID wird beim Anlegen ausgegeben und kodiert die Koordinator-ID als Praefix.

## Hinweise zu v1

- Ein Koordinator verarbeitet immer nur einen Job gleichzeitig.
- Fehlgeschlagene Subtasks werden im Bericht vermerkt und nicht automatisch wiederholt.
- GPS-Ausfaelle werden defensiv behandelt, aber es gibt keine alternative Navigation ohne GPS.
- Kollisionsvermeidung zwischen Arbeitern ist auf getrennte Y-Schichten beschraenkt.
- Die physische Koordinator-Navigation zum Einsammeln ist bewusst einfach gehalten und setzt ein kontrolliertes Dock-Layout voraus.
