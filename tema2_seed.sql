-- =========================================
-- SEED TEMA 2 - Dados de teste
-- Cria dados mínimos para:
-- departamento, área, docente, curso, uc,
-- ano letivo, semestres, tipos de hora,
-- tipos de sala, salas, turmas, janelas,
-- e uma aula.
-- =========================================

-- ---------- Departamento ----------
INSERT INTO departamento (nome, sigla)
VALUES ('Escola de Tecnologia', 'EST')
ON CONFLICT (sigla) DO NOTHING;

-- ---------- Área científica ----------
INSERT INTO area_cientifica (nome, sigla, departamento_id)
VALUES (
  'Informática',
  'INF',
  (SELECT id FROM departamento WHERE sigla = 'EST')
)
ON CONFLICT (sigla) DO NOTHING;

-- ---------- Docente ----------
INSERT INTO docente (nome, regime, area_principal_id, email_institucional, ativo)
VALUES (
  'João Docente',
  'TI',
  (SELECT id FROM area_cientifica WHERE sigla = 'INF'),
  'joao.docente@ips.pt',
  TRUE
)
ON CONFLICT (email_institucional) DO NOTHING;

-- ---------- Tipo de curso ----------
INSERT INTO tipo_curso (nome)
VALUES ('Licenciatura')
ON CONFLICT (nome) DO NOTHING;

-- ---------- Curso ----------
INSERT INTO curso (nome, sigla, tipo_id, ativo)
VALUES (
  'Licenciatura em Informática',
  'LEI',
  (SELECT id FROM tipo_curso WHERE nome = 'Licenciatura'),
  TRUE
)
ON CONFLICT (sigla) DO NOTHING;

-- ---------- Ano letivo ----------
INSERT INTO ano_letivo (label, data_inicio, data_fim)
VALUES ('2025/2026', '2025-09-15', '2026-07-31')
ON CONFLICT (label) DO NOTHING;

-- ---------- Semestres ----------
INSERT INTO semestre_letivo (ano_id, numero, data_inicio, data_fim)
VALUES
  (
    (SELECT id FROM ano_letivo WHERE label = '2025/2026'),
    1,
    '2025-09-15',
    '2026-02-15'
  ),
  (
    (SELECT id FROM ano_letivo WHERE label = '2025/2026'),
    2,
    '2026-02-16',
    '2026-07-31'
  )
ON CONFLICT (ano_id, numero) DO NOTHING;

-- ---------- Tipos de hora ----------
INSERT INTO tipo_hora (codigo, descricao)
VALUES
  ('T',  'Teórica'),
  ('TP', 'Teórico-Prática'),
  ('PL', 'Práticas de Laboratório')
ON CONFLICT (codigo) DO NOTHING;

-- ---------- UC ----------
INSERT INTO uc (codigo, nome, ects, horas_semanais, tipo, area_id, responsavel_id)
VALUES (
  'BD1',
  'Bases de Dados I',
  6,
  4,
  'OBR',
  (SELECT id FROM area_cientifica WHERE sigla = 'INF'),
  (SELECT id FROM docente WHERE email_institucional = 'joao.docente@ips.pt')
)
ON CONFLICT (codigo) DO NOTHING;

-- ---------- Curso ↔ UC ----------
INSERT INTO curso_uc (curso_id, uc_id, ano_curricular, semestre_id)
VALUES (
  (SELECT id FROM curso WHERE sigla = 'LEI'),
  (SELECT id FROM uc WHERE codigo = 'BD1'),
  2,
  (SELECT s.id
   FROM semestre_letivo s
   JOIN ano_letivo a ON s.ano_id = a.id
   WHERE a.label = '2025/2026' AND s.numero = 1)
)
ON CONFLICT (curso_id, uc_id) DO NOTHING;

-- ---------- Horas por tipo na UC ----------
INSERT INTO uc_tipo_hora (uc_id, tipo_hora_id, horas)
VALUES
  (
    (SELECT id FROM uc WHERE codigo = 'BD1'),
    (SELECT id FROM tipo_hora WHERE codigo = 'T'),
    1
  ),
  (
    (SELECT id FROM uc WHERE codigo = 'BD1'),
    (SELECT id FROM tipo_hora WHERE codigo = 'TP'),
    2
  ),
  (
    (SELECT id FROM uc WHERE codigo = 'BD1'),
    (SELECT id FROM tipo_hora WHERE codigo = 'PL'),
    1
  )
ON CONFLICT (uc_id, tipo_hora_id) DO NOTHING;

-- =========================================
--   TEMA 2 - Salas, turmas, janelas, aulas
-- =========================================

-- ---------- Tipos de sala ----------
INSERT INTO tipo_sala (codigo, descricao)
VALUES
  ('TEO', 'Sala Teórica'),
  ('LAB', 'Laboratório de Informática')
ON CONFLICT (codigo) DO NOTHING;

-- ---------- Salas ----------
INSERT INTO sala (nome, edificio, campus, tipo_sala_id, lotacao, ativo)
VALUES
  (
    'A1.01',
    'Edifício A',
    'Santarém',
    (SELECT id FROM tipo_sala WHERE codigo = 'TEO'),
    40,
    TRUE
  ),
  (
    'LAB-1',
    'Edifício A',
    'Santarém',
    (SELECT id FROM tipo_sala WHERE codigo = 'LAB'),
    25,
    TRUE
  )
ON CONFLICT (nome) DO NOTHING;

-- ---------- Turma ----------
INSERT INTO turma (curso_id, uc_id, ano_letivo_id, semestre_id, designacao, numero_alunos, ativo)
VALUES (
  (SELECT id FROM curso WHERE sigla = 'LEI'),
  (SELECT id FROM uc WHERE codigo = 'BD1'),
  (SELECT id FROM ano_letivo WHERE label = '2025/2026'),
  (SELECT s.id
   FROM semestre_letivo s
   JOIN ano_letivo a ON s.ano_id = a.id
   WHERE a.label = '2025/2026' AND s.numero = 1),
  '1A',
  30,
  TRUE
)
ON CONFLICT (curso_id, uc_id, ano_letivo_id, semestre_id, designacao) DO NOTHING;

-- ---------- Janelas horárias ----------
-- 2ª feira 10:00–11:30
INSERT INTO janela_horaria (dia_semana, hora_inicio, hora_fim)
VALUES (1, '10:00', '11:30')
ON CONFLICT (dia_semana, hora_inicio, hora_fim) DO NOTHING;

-- ---------- Aula de teste ----------
-- Aula de BD1, turma 1A, na sala A1.01, dada pelo João Docente
INSERT INTO aula (turma_id, docente_id, sala_id, janela_id, tipo_hora_id, observacoes, ativo)
VALUES (
  (SELECT t.id FROM turma t
    JOIN uc u ON t.uc_id = u.id
   WHERE t.designacao = '1A' AND u.codigo = 'BD1'),
  (SELECT id FROM docente WHERE email_institucional = 'joao.docente@ips.pt'),
  (SELECT id FROM sala WHERE nome = 'A1.01'),
  (SELECT id FROM janela_horaria WHERE dia_semana = 1 AND hora_inicio = '10:00' AND hora_fim = '11:30'),
  (SELECT id FROM tipo_hora WHERE codigo = 'T'),
  'Aula de teste - BD1',
  TRUE
);
