# Changelog

## 1.2.0 - 2026-11-13

- aggiunti `foundry_target_version` e `install_target_version` per aggiornamenti
  manuali e una tantum;
- supportati versione esplicita, URL temporaneo e credenziali Foundry;
- aggiunte validazione preventiva, installazione transazionale e idempotenza;
- aggiunto il rollback automatico se il primo avvio non supera il controllo;
- separato l'avanzamento di versione da `force_download`;
- preservati esplicitamente mondi, configurazioni, backup e log.

## 1.1.0 - 2026-09-20

- rimossa l'opzione di avvio `--noupdate`;
- resa persistente l'installazione applicativa in `/config/foundry_app`;
- gli aggiornamenti Foundry 14 installati dalla UI sopravvivono ai riavvii;
- `force_download` ora ripristina anche l'installazione applicativa prevista dall'immagine;
- aggiunte avvertenze su backup e aggiornamenti tra generazioni diverse.

## 1.0.11 - 2026-09-20

- aggiunti icona e logo per lo Store degli add-on;
- aggiunte documentazione e introduzione visualizzate da Home Assistant;
- aggiunto il collegamento per installare il repository con un clic;
- migliorata la visibilità del progetto su GitHub.

## 1.0.10 - 2026-09-11

- prima versione pubblica per Foundry Virtual Tabletop 14;
- dati persistenti in `/config` con cache del pacchetto;
- collegamenti alle cartelle HAOS `media` e `share`;
- opzione `force_download` e conservazione della configurazione.
