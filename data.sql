-- Responsables
INSERT INTO persona (nombre, correo, telefono, tipo_persona) VALUES
('Ana Morales', 'ana@centro.org', '5551-1111', 'responsable'),
('Carlos Pérez', 'carlos@centro.org', '5551-2222', 'responsable'),
('María López', 'maria@centro.org', '5551-3333', 'responsable'),
('Luis Gómez', 'luis@centro.org', '5551-4444', 'responsable'),
('Patricia Ríos', 'patricia@centro.org', '5551-5555', 'responsable'),
('Esteban Díaz', 'esteban@centro.org', '5551-6666', 'responsable'),
('Javier Soto', 'javier@centro.org', '5551-7777', 'responsable'),
('Marta Aguilar', 'marta@centro.org', '5551-8888', 'responsable'),
('Ricardo Méndez', 'ricardo@centro.org', '5551-9999', 'responsable'),
('Lucía Herrera', 'lucia@centro.org', '5552-0000', 'responsable');

-- Participantes
DO $$
BEGIN
    FOR i IN 1..40 LOOP
        INSERT INTO persona (nombre, correo, telefono, tipo_persona)
        VALUES (
            'Participante ' || i,
            'p' || i || '@correo.com',
            '5553-' || LPAD(i::text, 4, '0'),
            'participante'
        );
    END LOOP;
END $$;

-- Actividades
DO $$
BEGIN
    FOR i IN 1..50 LOOP
        INSERT INTO actividad (nombre, descripcion, fecha, hora, capacidad, id_responsable)
        VALUES (
            'Actividad ' || i,
            'Descripción de la actividad ' || i,
            DATE '2025-06-01' + (i % 30),
            TIME '08:00' + (i % 10) * INTERVAL '1 hour',
            10 + (i % 15),
            ((i - 1) % 10) + 1  -- IDs de responsables del 1 al 10
        );
    END LOOP;
END $$;

-- Inscripciones
DO $$
DECLARE
    pid INT;
    acts INT[];
    act_count INT;
BEGIN
    FOR pid IN 11..50 LOOP
        act_count := 3 + (RANDOM() < 0.5)::INT;
        acts := ARRAY(
            SELECT id_actividad FROM actividad ORDER BY RANDOM() LIMIT act_count
        );
        FOREACH a IN ARRAY acts LOOP
            BEGIN
                INSERT INTO inscripcion (id_persona, id_actividad) VALUES (pid, a);
            EXCEPTION WHEN unique_violation THEN
                CONTINUE;
            END;
        END LOOP;
    END LOOP;
END $$;
