# Foundry VTT HAOS

![FoundryOnHAOS](logo.png)

> **Add-on non ufficiale e non affiliato a Foundry Gaming LLC, al progetto `felddy/foundryvtt-docker` o a Home Assistant.**

Esegue Foundry Virtual Tabletop 14 come add-on gestito da Home Assistant OS usando l'immagine [`ghcr.io/felddy/foundryvtt:14`](https://github.com/felddy/foundryvtt-docker).

## Funzioni principali

- dati persistenti in `/config`;
- cache persistente del pacchetto Foundry;
- aggiornamenti software installabili dalla UI di Foundry e persistenti;
- cartelle HAOS `media` e `share` disponibili in `Data/assets`;
- porta esterna configurabile dalla UI di Home Assistant;
- download forzato soltanto quando richiesto;
- permessi automatici `1000:1000` per l'utente `node`.

Foundry Virtual Tabletop non è incluso nell'add-on. Per utilizzarlo servono un account e una licenza Foundry VTT validi.

Consulta la scheda **Documentazione** dopo l'installazione per la configurazione completa.
