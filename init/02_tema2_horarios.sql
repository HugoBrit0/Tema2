-- =========================================
-- TEMA 2 - PLANEAMENTO E GESTÃO DE HORÁRIOS
-- Tabelas: tipo_sala, sala, turma, janela_horaria, aula
-- Regras:
--  - EXCLUDE (docente, janela) e (sala, janela)
--  - Trigger lotação sala >= alunos turma
-- =========================================

-- ---------- Tipos de sala ----------
CREATE TABLE IF NOT EXISTS tipo_sala (
  id           SERIAL PRIMARY KEY,
  codigo       TEXT NOT NULL UNIQUE,       -- ex: 'TEO', 'LAB', 'TP', 'AUD'
  descricao    TEXT
);

-- ---------- Salas ----------
CREATE TABLE IF NOT EXISTS sala (
  id           SERIAL PRIMARY KEY,
  nome         TEXT NOT NULL,              -- ex: 'A1.01'
  edificio     TEXT,
  campus       TEXT,
  tipo_sala_id INT NOT NULL REFERENCES tipo_sala(id)
                ON UPDATE CASCADE ON DELETE RESTRICT,
  lotacao      INT NOT NULL CHECK (lotacao > 0),
  ativo        BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT uq_sala_nome UNIQUE (nome)
);

-- ---------- Turmas ----------
CREATE TABLE IF NOT EXISTS turma (
  id             SERIAL PRIMARY KEY,
  curso_id       INT NOT NULL REFERENCES curso(id)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
  uc_id          INT NOT NULL REFERENCES uc(id)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
  ano_letivo_id  INT NOT NULL REFERENCES ano_letivo(id)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
  semestre_id    INT NOT NULL REFERENCES semestre_letivo(id)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
  designacao     TEXT NOT NULL,            -- ex: '1A'
  numero_alunos  INT NOT NULL CHECK (numero_alunos > 0),
  ativo          BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT uq_turma_uc_semestre UNIQUE (curso_id, uc_id, ano_letivo_id, semestre_id, designacao)
);

-- ---------- Janelas horárias ----------
CREATE TABLE IF NOT EXISTS janela_horaria (
  id           SERIAL PRIMARY KEY,
  dia_semana   SMALLINT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7), -- 1=Seg ... 7=Dom
  hora_inicio  TIME NOT NULL,
  hora_fim     TIME NOT NULL,
  duracao_min  INT GENERATED ALWAYS AS (EXTRACT(EPOCH FROM (hora_fim - hora_inicio))::INT / 60) STORED,
  CONSTRAINT ck_janela_intervalo_valido CHECK (hora_fim > hora_inicio),
  CONSTRAINT uq_janela UNIQUE (dia_semana, hora_inicio, hora_fim)
);

-- ---------- Aulas ----------
CREATE TABLE IF NOT EXISTS aula (
  id             SERIAL PRIMARY KEY,
  turma_id       INT NOT NULL REFERENCES turma(id)
                  ON UPDATE CASCADE ON DELETE CASCADE,
  docente_id     INT NOT NULL REFERENCES docente(id)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
  sala_id        INT NOT NULL REFERENCES sala(id)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
  janela_id      INT NOT NULL REFERENCES janela_horaria(id)
                  ON UPDATE CASCADE ON DELETE RESTRICT,
  tipo_hora_id   INT REFERENCES tipo_hora(id)
                  ON UPDATE CASCADE ON DELETE SET NULL,
  observacoes    TEXT,
  ativo          BOOLEAN NOT NULL DEFAULT TRUE
);

-- Extensão para EXCLUDE com inteiros
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------- Conflitos (hard constraints) ----------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'excl_aula_docente_janela'
  ) THEN
    ALTER TABLE aula
    ADD CONSTRAINT excl_aula_docente_janela
    EXCLUDE USING gist (
      docente_id WITH =,
      janela_id  WITH =
    );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'excl_aula_sala_janela'
  ) THEN
    ALTER TABLE aula
    ADD CONSTRAINT excl_aula_sala_janela
    EXCLUDE USING gist (
      sala_id   WITH =,
      janela_id WITH =
    );
  END IF;
END $$;

-- ---------- Trigger lotação ----------
CREATE OR REPLACE FUNCTION trg_aula_check_lotacao()
RETURNS trigger AS $$
DECLARE
  v_lotacao INT;
  v_n_alunos INT;
BEGIN
  SELECT s.lotacao INTO v_lotacao
    FROM sala s
   WHERE s.id = NEW.sala_id;

  SELECT t.numero_alunos INTO v_n_alunos
    FROM turma t
   WHERE t.id = NEW.turma_id;

  IF v_lotacao IS NULL OR v_n_alunos IS NULL THEN
    RAISE EXCEPTION 'Sala ou turma inválidas para aula %', NEW.id;
  END IF;

  IF v_lotacao < v_n_alunos THEN
    RAISE EXCEPTION 'Lotação insuficiente: sala % (% lugares) < turma % (% alunos)',
      NEW.sala_id, v_lotacao, NEW.turma_id, v_n_alunos;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_aula_check_lotacao ON aula;

CREATE TRIGGER t_aula_check_lotacao
BEFORE INSERT OR UPDATE ON aula
FOR EACH ROW
EXECUTE FUNCTION trg_aula_check_lotacao();
