# Wiederherstellung

## Gewoehnliche Blockierungen

- **Kohletruhe leer:** Kohle/Holzkohle nachlegen. Auch der Verwalter benoetigt eine eigene Fahrreserve.
- **Ergebnislager voll:** Platz schaffen. Transporte bleiben offen; Erfolg wird erst nach Einlagerung gemeldet.
- **Zutaten fehlen:** Sortenreine Quelle auffuellen oder fehlende Quelle nach sauberem Abbruch neu konfigurieren.
- **Kein passender Beruf:** Auftrag abbrechen, passende vorinstallierte Turtle bereitstellen, Zahl/Parkplaetze pruefen und Auftrag neu anlegen.
- **Kein Zugang/Serviceplatz:** Einen freien Weg und Platz fuer zwei benachbarte Turtles herstellen, dann `flotte weiter`.
- **GPS/Funk fehlt:** Infrastruktur wiederherstellen und `flotte weiter`. Verlorene Arbeiter werden nicht automatisch ersetzt. Keine fremden Turtles auf reservierte Positionen stellen.

Ein normaler Neustart laedt den letzten gueltigen Zustand und gleicht Arbeiter sowie offene Bewegungen ab. Turtles nicht zwischenzeitlich umsetzen. Die Blickrichtung wird nur aus bestaetigten Drehungen beziehungsweise GPS-kontrollierter Bewegung abgeleitet.

## Physische Aktionen waehrend eines Ausfalls

Unterbrochene Bewegungen werden anhand der gespeicherten Vorher-/Nachherposition mit GPS verglichen. Nach einer unklaren Drehung ist eine erneute Kalibrierung mit freiem Platz erforderlich. Falls die Einrichtungsausrichtung nicht mehr stimmt, die angezeigte Blickrichtung pruefen, bevor die Flotte weiterarbeitet.

Unterbrochene Transfers werden aus der lokalen Inventardifferenz gebucht. Waehrend der Wiederherstellung keine Gegenstaende manuell aus den beteiligten Turtles entfernen oder hineinlegen. Abholungen verwenden dieselbe Uebergabe-ID weiter, damit bereits geleerte Slots nicht erneut als neue Lieferung gelten.

Ein Crafting-Neustart darf nur automatisch als erfolgreich gelten, wenn Produkt und Restgegenstaende genau dem registrierten Rezept entsprechen. Ist der Zustand uneindeutig, blockiert die Turtle. In diesem Fall Inventare und Zustand sichern; die Zutaten-/Ergebnismengen mit dem Rezept abgleichen. `flotte weiter pruefen:ja` fordert eine erneute Pruefung an und erlaubt keine blinde erneute Fertigung eines ungeklaerten Ergebnisses.

Beim Aussetzen und Einsammeln werden Nachbar-Computer-ID, Beschriftung beziehungsweise der reservierte Inventarplatz abgeglichen. Wenn diese Pruefung scheitert, den Zustand nicht durch erneutes Aussetzen weiterer Arbeiter umgehen. Zuerst pruefen, ob die Turtle noch in der Welt, im Verwalter oder bereits in der Starttruhe ist.

Sind alle drei Zustandsgenerationen beschaedigt oder passen Welt und Journal nach manuellen Eingriffen nicht mehr zusammen, gibt es absichtlich keine automatische Reparatur: zuerst `.flotte/` und alle Inventare sichern. Danach alle beteiligten Turtles manuell stoppen, Gegenstaende/Arbeiter bergen und die defekten Zustandsdateien ausserhalb von `.flotte/` archivieren. Erst mit vollstaendig geborgener Flotte einen neuen Zustand einrichten. Ein unvollstaendiger Auftrag darf dabei nicht als erfolgreich uebernommen werden.

## Update zuruecksetzen

Nur bei gestoppter und eingelagerter Flotte: den Pfad in `.flotte/active.bak` pruefen und als `.flotte/active` wiederherstellen. Die vorherige Releaseadresse verweist auf ein vollstaendiges Paket. Keine Releaseverzeichnisse oder Zustandsdateien waehrend laufender Arbeit loeschen. Ein Downgrade auf v1 kann keine v2-Auftraege uebernehmen.
