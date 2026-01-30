
-- =====================================================
--  DSD SCHEMA (PostgreSQL) - Departments, Areas, Faculty,
--  Degrees/Titles history, Academic calendar, Courses/UCs,
--  DSD allocations, Users/RBAC, Documents, Contracts (+CTC),
--  Hiring pool (Bolsa), Contract Documents with Versioning.
-- =====================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- =========================
-- Core Organizational Entities
-- =========================
CREATE TABLE departamento (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL,
  sigla            TEXT NOT NULL UNIQUE,
  periodo          DATERANGE NOT NULL DEFAULT daterange(CURRENT_DATE, 'infinity', '[)'),
  CHECK (lower(periodo) < upper(periodo) OR upper_inf(periodo))
);

CREATE TABLE area_cientifica (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL,
  sigla            TEXT NOT NULL UNIQUE,
  departamento_id  INT NOT NULL REFERENCES departamento(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  periodo          DATERANGE NOT NULL DEFAULT daterange(CURRENT_DATE, 'infinity', '[)'),
  CHECK (lower(periodo) < upper(periodo) OR upper_inf(periodo))
);

-- Ensure area period is contained within department period
CREATE OR REPLACE FUNCTION trg_area_within_departamento()
RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM departamento d
     WHERE d.id = NEW.departamento_id AND NEW.periodo <@ d.periodo
  ) THEN
    RAISE EXCEPTION 'Período da área % fora do período do departamento %', NEW.periodo, NEW.departamento_id;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER t_area_within_departamento
BEFORE INSERT OR UPDATE ON area_cientifica
FOR EACH ROW EXECUTE FUNCTION trg_area_within_departamento();

-- =========================
-- Faculty (Docente) + Areas
-- =========================
CREATE TABLE grau (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL UNIQUE,
  ordem_academica  INT,
  CHECK (ordem_academica IS NULL OR ordem_academica >= 0)
);

CREATE TABLE titulo (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL UNIQUE,
  descricao        TEXT
);

CREATE TABLE docente (
  id                       SERIAL PRIMARY KEY,
  nome                     TEXT NOT NULL,
  regime                   TEXT NOT NULL CHECK (regime IN ('TI','TP')),
  area_principal_id        INT REFERENCES area_cientifica(id) ON UPDATE CASCADE ON DELETE SET NULL,
  email_institucional      TEXT UNIQUE,
  ativo                    BOOLEAN NOT NULL DEFAULT TRUE
);

-- Historic degrees/titles
CREATE TABLE historico_grau_docente (
  id               SERIAL PRIMARY KEY,
  docente_id       INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE CASCADE,
  grau_id          INT NOT NULL REFERENCES grau(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  periodo          DATERANGE NOT NULL,
  fonte            TEXT,
  CHECK (lower(periodo) < upper(periodo) OR upper_inf(periodo)),
  EXCLUDE USING gist (docente_id WITH =, periodo WITH &&)
);

CREATE TABLE historico_titulo_docente (
  id               SERIAL PRIMARY KEY,
  docente_id       INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE CASCADE,
  titulo_id        INT NOT NULL REFERENCES titulo(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  area_id          INT REFERENCES area_cientifica(id) ON UPDATE CASCADE ON DELETE SET NULL,
  periodo          DATERANGE NOT NULL,
  observacoes      TEXT,
  CHECK (lower(periodo) < upper(periodo) OR upper_inf(periodo)),
  EXCLUDE USING gist (docente_id WITH =, titulo_id WITH =, periodo WITH &&)
);

CREATE TABLE docente_area (
  docente_id       INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE CASCADE,
  area_id          INT NOT NULL REFERENCES area_cientifica(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  PRIMARY KEY (docente_id, area_id)
);

-- =========================
-- Coordinators History (Dept & Area)
-- =========================
CREATE TABLE historico_coord_departamento (
  id               SERIAL PRIMARY KEY,
  departamento_id  INT NOT NULL REFERENCES departamento(id) ON UPDATE CASCADE ON DELETE CASCADE,
  docente_id       INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  periodo          DATERANGE NOT NULL,
  CHECK (lower(periodo) < upper(periodo) OR upper_inf(periodo)),
  EXCLUDE USING gist (departamento_id WITH =, periodo WITH &&)
);

CREATE TABLE historico_coord_area (
  id               SERIAL PRIMARY KEY,
  area_id          INT NOT NULL REFERENCES area_cientifica(id) ON UPDATE CASCADE ON DELETE CASCADE,
  docente_id       INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  periodo          DATERANGE NOT NULL,
  CHECK (lower(periodo) < upper(periodo) OR upper_inf(periodo)),
  EXCLUDE USING gist (area_id WITH =, periodo WITH &&)
);

CREATE OR REPLACE FUNCTION trg_coord_dept_period_within_dept()
RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM departamento d
    WHERE d.id = NEW.departamento_id AND NEW.periodo <@ d.periodo
  ) THEN
    RAISE EXCEPTION 'Período do coordenador % fora do período do departamento %', NEW.periodo, NEW.departamento_id;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER t_coord_dept_chk
BEFORE INSERT OR UPDATE ON historico_coord_departamento
FOR EACH ROW EXECUTE FUNCTION trg_coord_dept_period_within_dept();

CREATE OR REPLACE FUNCTION trg_coord_area_period_within_area()
RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM area_cientifica a
    WHERE a.id = NEW.area_id AND NEW.periodo <@ a.periodo
  ) THEN
    RAISE EXCEPTION 'Período do coordenador % fora do período da área %', NEW.periodo, NEW.area_id;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER t_coord_area_chk
BEFORE INSERT OR UPDATE ON historico_coord_area
FOR EACH ROW EXECUTE FUNCTION trg_coord_area_period_within_area();

-- =========================
-- Academic Calendar
-- =========================
CREATE TABLE ano_letivo (
  id               SERIAL PRIMARY KEY,
  label            TEXT NOT NULL UNIQUE,   -- '2025/2026'
  data_inicio      DATE NOT NULL,
  data_fim         DATE NOT NULL,
  CHECK (data_fim > data_inicio)
);

CREATE TABLE semestre_letivo (
  id               SERIAL PRIMARY KEY,
  ano_id           INT NOT NULL REFERENCES ano_letivo(id) ON UPDATE CASCADE ON DELETE CASCADE,
  numero           INT NOT NULL CHECK (numero IN (1,2)),
  data_inicio      DATE NOT NULL,
  data_fim         DATE NOT NULL,
  UNIQUE (ano_id, numero),
  CHECK (data_fim > data_inicio)
);

-- =========================
-- Courses & UCs (DSD scope)
-- =========================
CREATE TABLE tipo_curso (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL UNIQUE
);

CREATE TABLE curso (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL,
  sigla            TEXT NOT NULL UNIQUE,
  tipo_id          INT NOT NULL REFERENCES tipo_curso(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  ativo            BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE uc (
  id               SERIAL PRIMARY KEY,
  codigo           TEXT UNIQUE,
  nome             TEXT NOT NULL,
  ects             INT CHECK (ects IS NULL OR ects >= 0),
  horas_semanais   INT CHECK (horas_semanais IS NULL OR horas_semanais >= 0),
  tipo             TEXT NOT NULL CHECK (tipo IN ('OBR','OPT')),
  area_id          INT NOT NULL REFERENCES area_cientifica(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  responsavel_id   INT REFERENCES docente(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE curso_uc (
  curso_id         INT NOT NULL REFERENCES curso(id) ON UPDATE CASCADE ON DELETE CASCADE,
  uc_id            INT NOT NULL REFERENCES uc(id) ON UPDATE CASCADE ON DELETE CASCADE,
  ano_curricular   INT NOT NULL CHECK (ano_curricular BETWEEN 1 AND 6),
  semestre_id      INT NOT NULL REFERENCES semestre_letivo(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  PRIMARY KEY (curso_id, uc_id)
);

-- Types of hours per UC (T/TP/PL)
CREATE TABLE tipo_hora (
  id               SERIAL PRIMARY KEY,
  codigo           TEXT NOT NULL UNIQUE,  -- 'T','TP','PL',...
  descricao        TEXT
);

CREATE TABLE uc_tipo_hora (
  uc_id            INT NOT NULL REFERENCES uc(id) ON UPDATE CASCADE ON DELETE CASCADE,
  tipo_hora_id     INT NOT NULL REFERENCES tipo_hora(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  horas            INT NOT NULL CHECK (horas >= 0),
  PRIMARY KEY (uc_id, tipo_hora_id)
);

-- Docente assigned to UC in a given semester (DSD)
CREATE TABLE docente_uc (
  id               SERIAL PRIMARY KEY,
  docente_id       INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  uc_id            INT NOT NULL REFERENCES uc(id) ON UPDATE CASCADE ON DELETE CASCADE,
  semestre_id      INT NOT NULL REFERENCES semestre_letivo(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  horas_atribuicao INT,
  observacoes      TEXT,
  UNIQUE (docente_id, uc_id, semestre_id)
);

-- Optional granularity per hour-type
CREATE TABLE docente_uc_tipo_hora (
  docente_uc_id    INT NOT NULL REFERENCES docente_uc(id) ON UPDATE CASCADE ON DELETE CASCADE,
  tipo_hora_id     INT NOT NULL REFERENCES tipo_hora(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  horas            INT NOT NULL CHECK (horas >= 0),
  PRIMARY KEY (docente_uc_id, tipo_hora_id)
);

-- =========================
-- Users & RBAC
-- =========================
CREATE TABLE utilizador (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL,
  email            TEXT NOT NULL UNIQUE,
  password_hash    TEXT NOT NULL,
  ativo            BOOLEAN NOT NULL DEFAULT TRUE,
  docente_id       INT REFERENCES docente(id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE TABLE role (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL UNIQUE,
  descricao        TEXT
);

CREATE TABLE permissao (
  id               SERIAL PRIMARY KEY,
  codigo           TEXT NOT NULL UNIQUE,
  descricao        TEXT
);

CREATE TABLE role_permissao (
  role_id          INT NOT NULL REFERENCES role(id) ON UPDATE CASCADE ON DELETE CASCADE,
  permissao_id     INT NOT NULL REFERENCES permissao(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (role_id, permissao_id)
);

CREATE TABLE utilizador_role (
  utilizador_id    INT NOT NULL REFERENCES utilizador(id) ON UPDATE CASCADE ON DELETE CASCADE,
  role_id          INT NOT NULL REFERENCES role(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (utilizador_id, role_id)
);

-- =========================
-- Documents & Attachments
-- =========================
CREATE TABLE tipo_documento (
  id               SERIAL PRIMARY KEY,
  codigo           TEXT NOT NULL UNIQUE,  -- 'CV','PARECER_AREA','PARECER_DEPART','CONTRATO','APROVACAO_CTC',...
  descricao        TEXT
);

CREATE TABLE documento (
  id               SERIAL PRIMARY KEY,
  tipo_id          INT NOT NULL REFERENCES tipo_documento(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  nome_ficheiro    TEXT NOT NULL,
  mime_type        TEXT,
  tamanho_bytes    BIGINT,
  hash_sha256      TEXT,
  url_armazenamento TEXT NOT NULL,
  criado_em        TIMESTAMP NOT NULL DEFAULT now(),
  criado_por       INT REFERENCES utilizador(id) ON UPDATE CASCADE ON DELETE SET NULL,
  observacoes      TEXT
);

-- =========================
-- Hiring / Contracts (+CTC approval) with versioned docs
-- =========================
CREATE TABLE categoria_docente (
  id               SERIAL PRIMARY KEY,
  nome             TEXT NOT NULL UNIQUE,
  max_horas_semanais INT CHECK (max_horas_semanais IS NULL OR max_horas_semanais > 0)
);

CREATE TABLE contrato_docente (
  id               SERIAL PRIMARY KEY,
  docente_id       INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE CASCADE,
  categoria_id     INT NOT NULL REFERENCES categoria_docente(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  tipo_contrato    TEXT NOT NULL CHECK (tipo_contrato IN ('SemTermo','ATermo')),
  horas_semanais   INT NOT NULL CHECK (horas_semanais > 0),
  periodo          DATERANGE NOT NULL,
  semestre_inicio  INT CHECK (semestre_inicio IN (1,2)),
  semestre_fim     INT CHECK (semestre_fim IN (1,2)),
  observacoes      TEXT,
  -- CTC approval
  data_aprov_ctc   DATE,
  doc_aprov_ctc_id INT REFERENCES documento(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CHECK (lower(periodo) < upper(periodo) OR upper_inf(periodo)),
  EXCLUDE USING gist (docente_id WITH =, periodo WITH &&)
);

-- Versioned documents per contract (only one active per type)
CREATE TABLE contrato_doc_hist (
  id               SERIAL PRIMARY KEY,
  contrato_id      INT NOT NULL REFERENCES contrato_docente(id) ON UPDATE CASCADE ON DELETE CASCADE,
  tipo_doc_id      INT NOT NULL REFERENCES tipo_documento(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  documento_id     INT NOT NULL REFERENCES documento(id) ON UPDATE CASCADE ON DELETE CASCADE,
  ativo            BOOLEAN NOT NULL DEFAULT TRUE,
  criado_em        TIMESTAMP NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX ux_contrato_doc_ativo
  ON contrato_doc_hist (contrato_id, tipo_doc_id) WHERE ativo = TRUE;

CREATE OR REPLACE FUNCTION trg_contrato_doc_only_one_active()
RETURNS trigger AS $$
BEGIN
  UPDATE contrato_doc_hist
     SET ativo = FALSE
   WHERE contrato_id = NEW.contrato_id
     AND tipo_doc_id = NEW.tipo_doc_id
     AND ativo = TRUE;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER t_contrato_doc_only_one_active
BEFORE INSERT ON contrato_doc_hist
FOR EACH ROW EXECUTE FUNCTION trg_contrato_doc_only_one_active();

-- Optional: richer metadata for AREA/DEPART opinions
CREATE TABLE parecer (
  id               SERIAL PRIMARY KEY,
  documento_id     INT NOT NULL REFERENCES documento(id) ON UPDATE CASCADE ON DELETE CASCADE,
  contrato_id      INT NOT NULL REFERENCES contrato_docente(id) ON UPDATE CASCADE ON DELETE CASCADE,
  tipo_parecer     TEXT NOT NULL CHECK (tipo_parecer IN ('AREA','DEPART')),
  coordenador_id   INT NOT NULL REFERENCES docente(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  data_parecer     DATE NOT NULL,
  conclusao        TEXT,
  observacoes      TEXT,
  UNIQUE (contrato_id, tipo_parecer)
);

-- =========================
-- Hiring Pool (Bolsa)
-- =========================
CREATE TABLE bolsa_candidato (
  id               SERIAL PRIMARY KEY,
  nome_completo    TEXT NOT NULL,
  email_pessoal    TEXT NOT NULL,
  contacto         TEXT,
  situacao         TEXT NOT NULL CHECK (situacao IN ('NuncaContratado','ExContratado','DocenteAtivo')),
  disponivel       BOOLEAN NOT NULL DEFAULT TRUE,
  data_entrada     DATE NOT NULL DEFAULT CURRENT_DATE,
  docente_id       INT REFERENCES docente(id) ON UPDATE CASCADE ON DELETE SET NULL,
  observacoes      TEXT
);

CREATE TABLE bolsa_candidato_area (
  candidato_id     INT NOT NULL REFERENCES bolsa_candidato(id) ON UPDATE CASCADE ON DELETE CASCADE,
  area_id          INT NOT NULL REFERENCES area_cientifica(id) ON UPDATE CASCADE ON DELETE RESTRICT,
  PRIMARY KEY (candidato_id, area_id)
);

CREATE TABLE bolsa_candidato_cv (
  id               SERIAL PRIMARY KEY,
  candidato_id     INT NOT NULL REFERENCES bolsa_candidato(id) ON UPDATE CASCADE ON DELETE CASCADE,
  versao           INT NOT NULL,
  documento_id     INT NOT NULL REFERENCES documento(id) ON UPDATE CASCADE ON DELETE CASCADE,
  data_upload      TIMESTAMP NOT NULL DEFAULT now(),
  paginas          INT,
  hash_sha256      TEXT,
  ativo            BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (candidato_id, versao)
);
