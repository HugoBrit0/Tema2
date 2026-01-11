-- =========================================
-- SEED TEMA 2 (VERSÃO FINAL)
-- Base completa para testes, API e gerador
-- =========================================

-- -------------------------
-- Tipos de sala
-- -------------------------
INSERT INTO tipo_sala (codigo, descricao)
VALUES
  ('TEO', 'Sala Teórica'),
  ('LAB', 'Laboratório de Informática')
ON CONFLICT (codigo) DO NOTHING;

-- -------------------------
-- Salas
-- -------------------------
INSERT INTO sala (nome, edificio, campus, tipo_sala_id, lotacao, ativo)
VALUES
  ('A1.01', 'Edifício A', 'Santarém',
    (SELECT id FROM tipo_sala WHERE codigo='TEO'), 40, TRUE),
  ('LAB-1', 'Edifício A', 'Santarém',
    (SELECT id FROM tipo_sala WHERE codigo='LAB'), 25, TRUE),
  ('LAB-2', 'Edifício A', 'Santarém',
    (SELECT id FROM tipo_sala WHERE codigo='LAB'), 35, TRUE)
ON CONFLICT (nome) DO NOTHING;

-- -------------------------
-- Docentes
-- -------------------------
INSERT INTO docente (nome, regime, email_institucional, ativo)
VALUES
  ('João Docente', 'TI', 'joao.docente@ips.pt', TRUE),
  ('Maria Silva', 'TI', 'maria.silva@ips.pt', TRUE),
  ('Pedro Costa', 'TP', 'pedro.costa@ips.pt', TRUE)
ON CONFLICT (email_institucional) DO NOTHING;

-- -------------------------
-- Janelas horárias
-- -------------------------
INSERT INTO janela_horaria (dia_semana, hora_inicio, hora_fim)
VALUES
  (1, '09:00', '10:30'),
  (1, '10:00', '11:30'),
  (1, '11:30', '13:00'),
  (1, '14:00', '15:30'),
  (2, '09:00', '10:30'),
  (2, '10:30', '12:00'),
  (3, '09:00', '10:30'),
  (4, '14:00', '15:30'),
  (5, '09:00', '10:30')
ON CONFLICT (dia_semana, hora_inicio, hora_fim) DO NOTHING;

-- -------------------------
-- Turma 1A (30 alunos)
-- -------------------------
INSERT INTO turma (
  curso_id,
  uc_id,
  ano_letivo_id,
  semestre_id,
  designacao,
  numero_alunos,
  ativo
)
VALUES (
  (SELECT id FROM curso WHERE sigla = 'LEI' LIMIT 1),
  (SELECT id FROM uc WHERE codigo = 'BD1' LIMIT 1),
  (SELECT id FROM ano_letivo WHERE label = '2025/2026' LIMIT 1),
  (
    SELECT s.id
      FROM semestre_letivo s
      JOIN ano_letivo a ON a.id = s.ano_id
     WHERE a.label = '2025/2026' AND s.numero = 1
     LIMIT 1
  ),
  '1A',
  30,
  TRUE
)
ON CONFLICT (curso_id, uc_id, ano_letivo_id, semestre_id, designacao) DO NOTHING;

-- -------------------------
-- Aula seed inicial
-- -------------------------
INSERT INTO aula (
  turma_id,
  docente_id,
  sala_id,
  janela_id,
  tipo_hora_id,
  observacoes,
  ativo
)
VALUES (
  (
    SELECT t.id
      FROM turma t
      JOIN uc u ON u.id = t.uc_id
     WHERE t.designacao = '1A' AND u.codigo = 'BD1'
     LIMIT 1
  ),
  (SELECT id FROM docente WHERE email_institucional='joao.docente@ips.pt' LIMIT 1),
  (SELECT id FROM sala WHERE nome='A1.01' LIMIT 1),
  (
    SELECT id
      FROM janela_horaria
     WHERE dia_semana=1 AND hora_inicio='10:00' AND hora_fim='11:30'
     LIMIT 1
  ),
  (SELECT id FROM tipo_hora WHERE codigo='T' LIMIT 1),
  'Aula seed inicial - BD1',
  TRUE
)
ON CONFLICT DO NOTHING;
