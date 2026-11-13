# Foundry VTT HAOS

![FoundryOnHAOS](logo.png)

> **Add-on non ufficiale e non affiliato a Foundry Gaming LLC, al progetto `felddy/foundryvtt-docker` o a Home Assistant.**

Esegue Foundry Virtual Tabletop 14 come add-on gestito da Home Assistant OS usando l'immagine [`ghcr.io/felddy/foundryvtt:14.370.0`](https://github.com/felddy/foundryvtt-docker).

## Funzioni principali

- dati persistenti in `/config`;
- cache persistente del pacchetto Foundry;
- aggiornamenti software installabili dalla UI di Foundry e persistenti;
- aggiornamento manuale a una build 14 scelta, con verifica e rollback;
- cartelle HAOS `media` e `share` disponibili in `Data/assets`;
- porta esterna configurabile dalla UI di Home Assistant;
- download forzato soltanto quando richiesto;
- permessi automatici `1000:1000` per l'utente `node`.

Foundry Virtual Tabletop non è incluso nell'add-on. Per utilizzarlo servono un account e una licenza Foundry VTT validi.

Parte del codice e della documentazione dell'adattamento HAOS è stata sviluppata
con il supporto di OpenAI Codex e revisionata dal maintainer.

Consulta la scheda **Documentazione** dopo l'installazione per la configurazione completa.

Per un aggiornamento controllato, indica `foundry_target_version`, oppure
fornisci un nuovo `foundry_release_url`, e attiva una sola volta
`install_target_version`. L'archivio viene verificato ed estratto in un'area
temporanea; l'applicazione precedente resta disponibile finché il nuovo avvio
non supera il controllo di salute. Questa operazione non modifica `Data`,
`Config`, `Backups` o `Logs`.

Se il controllo di avvio fallisce, porta `install_target_version` a `false`
prima di correggere la richiesta e riprovare: l'add-on non entra in un ciclo di
download automatici.
