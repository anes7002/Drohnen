-- Tabelle für die Drohnen-Verwaltung [cite: 86, 87]
CREATE TABLE drohne (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100), -- [cite: 67]
    ip_adresse VARCHAR(15) NOT NULL, -- [cite: 20, 24]
    mac_adresse VARCHAR(17) UNIQUE,
    erstellt_am TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabelle für aufgezeichnete Flugkurse [cite: 47, 48]
CREATE TABLE flugkurs (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL, -- [cite: 55]
    -- Speichert Liste von Commands (Zeitstempel, Befehl, Wert) [cite: 50, 52, 53, 54]
    commands JSONB NOT NULL, 
    aufgezeichnet_am TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Tabelle für Video-Metadaten [cite: 71]
CREATE TABLE video (
    id SERIAL PRIMARY KEY,
    drohnen_id INTEGER REFERENCES drohne(id) ON DELETE CASCADE,
    dateipfad TEXT NOT NULL, 
    aufnahmedatum TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);