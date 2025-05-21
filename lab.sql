-- Trigger BEFORE: Verificar que no se exceda la capacidad de una actividad
CREATE OR REPLACE FUNCTION verificar_capacidad_actividad()
RETURNS TRIGGER AS $$
DECLARE
    inscritos INTEGER;
    cap_max INTEGER;
BEGIN
    -- Obtener la cantidad actual de inscritos en la actividad
    SELECT COUNT(*) INTO inscritos 
    FROM inscripcion 
    WHERE id_actividad = NEW.id_actividad;
    
    -- Obtener la capacidad máxima de la actividad
    SELECT capacidad INTO cap_max 
    FROM actividad 
    WHERE id_actividad = NEW.id_actividad;
    
    -- Verificar si se excede la capacidad
    IF inscritos >= cap_max THEN
        RAISE EXCEPTION 'La actividad ha alcanzado su capacidad máxima de % participantes', cap_max;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger BEFORE
CREATE TRIGGER tr_verificar_capacidad_antes_inscripcion
BEFORE INSERT ON inscripcion
FOR EACH ROW
EXECUTE FUNCTION verificar_capacidad_actividad();

-- Procedimiento para notificar al responsable de la actividad
CREATE OR REPLACE PROCEDURE notificar_responsable(
    p_id_actividad INTEGER,
    p_id_persona INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_nombre_participante VARCHAR(100);
    v_nombre_actividad VARCHAR(100);
    v_responsable_correo VARCHAR(100);
    v_mensaje TEXT;
BEGIN
    -- Obtener información del participante, actividad y responsable
    SELECT p.nombre INTO v_nombre_participante 
    FROM persona p 
    WHERE p.id_persona = p_id_persona;
    
    SELECT a.nombre, r.correo INTO v_nombre_actividad, v_responsable_correo
    FROM actividad a
    JOIN persona r ON a.id_responsable = r.id_persona
    WHERE a.id_actividad = p_id_actividad;
    
    -- Construir mensaje de notificación
    v_mensaje := 'Se ha registrado una nueva inscripción. El participante ' || 
                v_nombre_participante || ' se ha inscrito en la actividad ' || 
                v_nombre_actividad;
    
    -- Aquí se simula el envío del correo
    -- En un entorno real, se utilizaría una extensión como pg_mail o una función para enviar correos
    RAISE NOTICE 'Enviando notificación a %: %', v_responsable_correo, v_mensaje;
    
    -- Registrar en log (simulado)
    RAISE INFO 'Nueva inscripción registrada: Actividad=%, Participante=%', 
                v_nombre_actividad, v_nombre_participante;
END;
$$;

-- Trigger AFTER: Notificar al responsable después de una inscripción
CREATE OR REPLACE FUNCTION notificar_nueva_inscripcion()
RETURNS TRIGGER AS $$
BEGIN
    -- Llamar al procedimiento para notificar al responsable
    CALL notificar_responsable(NEW.id_actividad, NEW.id_persona);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger AFTER
CREATE TRIGGER tr_notificar_despues_inscripcion
AFTER INSERT ON inscripcion
FOR EACH ROW
EXECUTE FUNCTION notificar_nueva_inscripcion();

-- 1. FUNCIÓN QUE RETORNA UN VALOR ESCALAR
-- Calcula el porcentaje de ocupación de una actividad
CREATE OR REPLACE FUNCTION calcular_porcentaje_ocupacion(p_id_actividad INT)
RETURNS NUMERIC AS $$
DECLARE
    v_capacidad INT;
    v_inscritos INT;
    v_porcentaje NUMERIC;
BEGIN
    -- Obtener capacidad de la actividad
    SELECT capacidad INTO v_capacidad
    FROM actividad
    WHERE id_actividad = p_id_actividad;
    
    -- Obtener cantidad de inscritos
    SELECT COUNT(*) INTO v_inscritos
    FROM inscripcion
    WHERE id_actividad = p_id_actividad;
    
    -- Calcular porcentaje
    IF v_capacidad = 0 THEN
        RETURN 0;
    ELSE
        v_porcentaje := (v_inscritos::NUMERIC / v_capacidad) * 100;
        RETURN ROUND(v_porcentaje, 2);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 2. FUNCIÓN QUE RETORNA UN CONJUNTO DE RESULTADOS
-- Obtiene las actividades disponibles para inscripción (con cupos)
CREATE OR REPLACE FUNCTION obtener_actividades_disponibles(p_fecha_inicio DATE, p_fecha_fin DATE)
RETURNS TABLE (
    id INT,
    nombre_actividad VARCHAR(100),
    nombre_responsable VARCHAR(100),
    fecha DATE,
    hora TIME,
    cupos_disponibles INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id_actividad, 
        a.nombre, 
        p.nombre, 
        a.fecha, 
        a.hora,
        a.capacidad - COUNT(i.id_inscripcion)::INT AS cupos_disponibles
    FROM 
        actividad a
    JOIN 
        persona p ON a.id_responsable = p.id_persona
    LEFT JOIN 
        inscripcion i ON a.id_actividad = i.id_actividad
    WHERE 
        a.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
    GROUP BY 
        a.id_actividad, a.nombre, p.nombre, a.fecha, a.hora, a.capacidad
    HAVING 
        a.capacidad - COUNT(i.id_inscripcion) > 0
    ORDER BY 
        a.fecha, a.hora;
END;
$$ LANGUAGE plpgsql;

-- 3. FUNCIÓN CON MÚLTIPLES PARÁMETROS Y LÓGICA CONDICIONAL
-- Recomienda actividades para un participante según diversos criterios
CREATE OR REPLACE FUNCTION recomendar_actividades(
    p_id_persona INT,
    p_fecha_inicio DATE DEFAULT CURRENT_DATE,
    p_preferencia_horario VARCHAR DEFAULT NULL,
    p_limite_resultados INT DEFAULT 5
)
RETURNS TABLE (
    id_actividad INT,
    nombre_actividad VARCHAR(100),
    fecha DATE,
    hora TIME,
    tipo_horario VARCHAR,
    cupos_disponibles INT,
    nivel_recomendacion VARCHAR
) AS $$
DECLARE
    v_tipo_horario VARCHAR;
    v_hora_preferida TIME;
BEGIN
    -- Determinar preferencia de horario
    IF p_preferencia_horario = 'mañana' THEN
        v_hora_preferida := '10:00:00'::TIME;
    ELSIF p_preferencia_horario = 'tarde' THEN
        v_hora_preferida := '16:00:00'::TIME;
    ELSE
        v_hora_preferida := '12:00:00'::TIME; -- horario neutral si no hay preferencia
    END IF;

    RETURN QUERY
    WITH actividades_disponibles AS (
        SELECT 
            a.id_actividad,
            a.nombre,
            a.fecha,
            a.hora,
            CASE 
                WHEN a.hora < '12:00:00'::TIME THEN 'mañana'
                WHEN a.hora >= '12:00:00'::TIME AND a.hora < '18:00:00'::TIME THEN 'tarde'
                ELSE 'noche'
            END AS tipo_horario,
            a.capacidad - COUNT(i.id_inscripcion)::INT AS cupos_disponibles
        FROM 
            actividad a
        LEFT JOIN 
            inscripcion i ON a.id_actividad = i.id_actividad
        WHERE 
            a.fecha >= p_fecha_inicio
        GROUP BY 
            a.id_actividad, a.nombre, a.fecha, a.hora, a.capacidad
        HAVING 
            a.capacidad - COUNT(i.id_inscripcion) > 0
    )
    SELECT 
        ad.id_actividad,
        ad.nombre,
        ad.fecha,
        ad.hora,
        ad.tipo_horario,
        ad.cupos_disponibles,
        CASE 
            WHEN NOT EXISTS (SELECT 1 FROM inscripcion WHERE id_persona = p_id_persona AND id_actividad = ad.id_actividad) 
                AND (p_preferencia_horario IS NULL OR ad.tipo_horario = p_preferencia_horario)
                THEN 'Alta'
            WHEN NOT EXISTS (SELECT 1 FROM inscripcion WHERE id_persona = p_id_persona AND id_actividad = ad.id_actividad)
                THEN 'Media'
            ELSE 'Baja'
        END AS nivel_recomendacion
    FROM 
        actividades_disponibles ad
    WHERE 
        NOT EXISTS (
            SELECT 1 FROM inscripcion 
            WHERE id_persona = p_id_persona AND id_actividad = ad.id_actividad
        )
    ORDER BY 
        CASE 
            WHEN p_preferencia_horario IS NULL THEN 0
            WHEN ad.tipo_horario = p_preferencia_horario THEN 1
            ELSE 2
        END,
        ABS(EXTRACT(EPOCH FROM (ad.hora - v_hora_preferida))),
        ad.fecha
    LIMIT p_limite_resultados;
END;
$$ LANGUAGE plpgsql;


-- 4. PROCEDIMIENTO PARA INSERCIONES COMPLEJAS
-- Registra un nuevo participante y lo inscribe en varias actividades
CREATE OR REPLACE PROCEDURE registrar_participante_con_actividades(
    p_nombre VARCHAR(100),
    p_correo VARCHAR(100),
    p_telefono VARCHAR(20),
    p_actividades INT[]
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_persona INT;
    v_id_actividad INT;
    v_contador INT := 0;
    v_actividades_inscritas TEXT := '';
    v_actividades_fallidas TEXT := '';
BEGIN
    -- Insertar nuevo participante
    INSERT INTO persona (nombre, correo, telefono, tipo_persona)
    VALUES (p_nombre, p_correo, p_telefono, 'participante')
    RETURNING id_persona INTO v_id_persona;
    
    -- Inscribir en actividades
    FOREACH v_id_actividad IN ARRAY p_actividades
    LOOP
        BEGIN
            INSERT INTO inscripcion (id_persona, id_actividad)
            VALUES (v_id_persona, v_id_actividad);
            
            v_contador := v_contador + 1;
            
            -- Agregar a lista de actividades inscritas exitosamente
            SELECT nombre INTO v_actividades_inscritas 
            FROM actividad 
            WHERE id_actividad = v_id_actividad;
            
            v_actividades_inscritas := v_actividades_inscritas || 
                                      CASE WHEN v_actividades_inscritas = '' THEN '' ELSE ', ' END || 
                                      v_actividades_inscritas;
                                      
        EXCEPTION
            WHEN OTHERS THEN
                -- Agregar a lista de actividades fallidas
                SELECT nombre INTO v_actividades_fallidas 
                FROM actividad 
                WHERE id_actividad = v_id_actividad;
                
                v_actividades_fallidas := v_actividades_fallidas || 
                                        CASE WHEN v_actividades_fallidas = '' THEN '' ELSE ', ' END || 
                                        v_actividades_fallidas || ' (Error: ' || SQLERRM || ')';
        END;
    END LOOP;
    
    -- Informar resultados
    RAISE NOTICE 'Participante % registrado con ID %', p_nombre, v_id_persona;
    RAISE NOTICE 'Inscrito exitosamente en % actividades: %', v_contador, v_actividades_inscritas;
    
    IF v_actividades_fallidas <> '' THEN
        RAISE NOTICE 'Falló inscripción en: %', v_actividades_fallidas;
    END IF;
END;
$$;

-- 5. PROCEDIMIENTO PARA ACTUALIZACIÓN CON VALIDACIONES
-- Cambia el responsable de una actividad, verificando disponibilidad y validez
CREATE OR REPLACE PROCEDURE cambiar_responsable_actividad(
    p_id_actividad INT,
    p_id_nuevo_responsable INT,
    p_fecha_cambio DATE DEFAULT CURRENT_DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_es_responsable BOOLEAN;
    v_nombre_actividad VARCHAR(100);
    v_responsable_actual INT;
    v_nombre_responsable_actual VARCHAR(100);
    v_nombre_nuevo_responsable VARCHAR(100);
    v_actividades_mismo_dia INT;
BEGIN
    -- Verificar que la actividad existe
    SELECT nombre, id_responsable INTO v_nombre_actividad, v_responsable_actual
    FROM actividad
    WHERE id_actividad = p_id_actividad;
    
    IF v_nombre_actividad IS NULL THEN
        RAISE EXCEPTION 'La actividad con ID % no existe', p_id_actividad;
    END IF;
    
    -- Verificar que el nuevo responsable es de tipo "responsable"
    SELECT nombre, tipo_persona = 'responsable' INTO v_nombre_nuevo_responsable, v_es_responsable
    FROM persona
    WHERE id_persona = p_id_nuevo_responsable;
    
    IF v_nombre_nuevo_responsable IS NULL THEN
        RAISE EXCEPTION 'La persona con ID % no existe', p_id_nuevo_responsable;
    END IF;
    
    IF NOT v_es_responsable THEN
        RAISE EXCEPTION 'La persona % no es un responsable válido', v_nombre_nuevo_responsable;
    END IF;
    
    -- Verificar que no es el mismo responsable
    IF v_responsable_actual = p_id_nuevo_responsable THEN
        RAISE EXCEPTION 'El responsable actual ya es %', v_nombre_nuevo_responsable;
    END IF;
    
    -- Obtener información del responsable actual
    SELECT nombre INTO v_nombre_responsable_actual
    FROM persona
    WHERE id_persona = v_responsable_actual;
    
    -- Verificar disponibilidad del nuevo responsable (máximo 3 actividades por día)
    SELECT COUNT(*) INTO v_actividades_mismo_dia
    FROM actividad
    WHERE id_responsable = p_id_nuevo_responsable
    AND fecha = (SELECT fecha FROM actividad WHERE id_actividad = p_id_actividad);
    
    IF v_actividades_mismo_dia >= 3 THEN
        RAISE EXCEPTION 'El responsable % ya tiene % actividades asignadas en ese día', 
                        v_nombre_nuevo_responsable, v_actividades_mismo_dia;
    END IF;
    
    -- Actualizar el responsable
    UPDATE actividad
    SET id_responsable = p_id_nuevo_responsable
    WHERE id_actividad = p_id_actividad;
    
    -- Registrar el cambio (simulado - en un sistema real esto podría ser en una tabla de auditoría)
    RAISE NOTICE 'Actividad: %', v_nombre_actividad;
    RAISE NOTICE 'Responsable anterior: %', v_nombre_responsable_actual;
    RAISE NOTICE 'Nuevo responsable: %', v_nombre_nuevo_responsable;
    RAISE NOTICE 'Fecha de cambio: %', p_fecha_cambio;
    
END;
$$;

-- 6. VISTA SIMPLE
-- Lista básica de actividades con sus responsables
CREATE OR REPLACE VIEW vista_actividades_responsables AS
SELECT 
    a.id_actividad,
    a.nombre AS nombre_actividad,
    a.fecha,
    a.hora,
    a.capacidad,
    p.nombre AS nombre_responsable,
    p.correo AS correo_responsable
FROM 
    actividad a
JOIN 
    persona p ON a.id_responsable = p.id_persona
ORDER BY 
    a.fecha, a.hora;

-- 7. VISTA CON JOIN Y GROUP BY
-- Resumen de inscripciones por actividad
CREATE OR REPLACE VIEW vista_resumen_inscripciones AS
SELECT 
    a.id_actividad,
    a.nombre AS nombre_actividad,
    p.nombre AS nombre_responsable,
    a.fecha,
    a.capacidad,
    COUNT(i.id_inscripcion) AS total_inscritos,
    a.capacidad - COUNT(i.id_inscripcion) AS cupos_disponibles,
    ROUND((COUNT(i.id_inscripcion)::NUMERIC / a.capacidad) * 100, 2) AS porcentaje_ocupacion
FROM 
    actividad a
JOIN 
    persona p ON a.id_responsable = p.id_persona
LEFT JOIN 
    inscripcion i ON a.id_actividad = i.id_actividad
GROUP BY 
    a.id_actividad, a.nombre, p.nombre, a.fecha, a.capacidad
ORDER BY 
    a.fecha, porcentaje_ocupacion DESC;

-- 8. VISTA CON EXPRESIONES CASE, COALESCE
-- Estado y clasificación de actividades
CREATE OR REPLACE VIEW vista_estado_actividades AS
SELECT 
    a.id_actividad,
    a.nombre,
    a.fecha,
    a.hora,
    CASE 
        WHEN a.fecha < CURRENT_DATE THEN 'Finalizada'
        WHEN a.fecha = CURRENT_DATE AND a.hora < CURRENT_TIME THEN 'En curso'
        WHEN a.fecha = CURRENT_DATE THEN 'Hoy'
        WHEN a.fecha <= CURRENT_DATE + INTERVAL '7 days' THEN 'Próxima semana'
        ELSE 'Futura'
    END AS estado_temporal,
    CASE 
        WHEN COUNT(i.id_inscripcion) = 0 THEN 'Sin inscripciones'
        WHEN COUNT(i.id_inscripcion) < a.capacidad * 0.5 THEN 'Baja ocupación'
        WHEN COUNT(i.id_inscripcion) < a.capacidad THEN 'Ocupación media'
        ELSE 'Completa'
    END AS estado_ocupacion,
    COALESCE(COUNT(i.id_inscripcion), 0) AS total_inscritos,
    COALESCE(a.capacidad - COUNT(i.id_inscripcion), a.capacidad) AS cupos_disponibles,
    COALESCE(p.nombre, 'Sin responsable') AS responsable
FROM 
    actividad a
LEFT JOIN 
    inscripcion i ON a.id_actividad = i.id_actividad
LEFT JOIN 
    persona p ON a.id_responsable = p.id_persona
GROUP BY 
    a.id_actividad, a.nombre, a.fecha, a.hora, a.capacidad, p.nombre
ORDER BY 
    a.fecha, a.hora;

-- 9. VISTA ADICIONAL: PARTICIPANTES POR ACTIVIDAD
CREATE OR REPLACE VIEW vista_participantes_por_actividad AS
SELECT 
    a.id_actividad,
    a.nombre AS nombre_actividad,
    a.fecha,
    a.hora,
    STRING_AGG(p.nombre, ', ' ORDER BY p.nombre) AS participantes,
    COUNT(p.id_persona) AS total_participantes,
    a.capacidad AS capacidad_maxima,
    a.capacidad - COUNT(p.id_persona) AS cupos_disponibles
FROM 
    actividad a
LEFT JOIN 
    inscripcion i ON a.id_actividad = i.id_actividad
LEFT JOIN 
    persona p ON i.id_persona = p.id_persona
GROUP BY 
    a.id_actividad, a.nombre, a.fecha, a.hora, a.capacidad
ORDER BY 
    a.fecha, a.hora;