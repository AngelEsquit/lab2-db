CREATE TABLE persona (
    id_persona SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    correo VARCHAR(100) UNIQUE NOT NULL,
    telefono VARCHAR(20),
    tipo_persona VARCHAR(20) CHECK (tipo_persona IN ('participante', 'responsable')) NOT NULL
);

CREATE TABLE actividad (
    id_actividad SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    fecha DATE NOT NULL,
    hora TIME NOT NULL,
    capacidad INT CHECK (capacidad > 0),
    id_responsable INT NOT NULL,
    FOREIGN KEY (id_responsable) REFERENCES persona(id_persona)
);

CREATE TABLE inscripcion (
    id_inscripcion SERIAL PRIMARY KEY,
    id_persona INT NOT NULL,
    id_actividad INT NOT NULL,
    fecha_inscripcion DATE DEFAULT CURRENT_DATE,
    FOREIGN KEY (id_persona) REFERENCES persona(id_persona),
    FOREIGN KEY (id_actividad) REFERENCES actividad(id_actividad),
    UNIQUE (id_persona, id_actividad)  -- evita doble inscripción
);
