CREATE TABLE calendar_events (
  id uuid PRIMARY KEY,
  owner_id smallint NOT NULL REFERENCES owner(id) ON DELETE CASCADE,
  event_date date NOT NULL,
  start_time time(0) NOT NULL,
  end_time time(0) NOT NULL,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 120),
  description text NOT NULL DEFAULT '' CHECK (length(description) <= 2000),
  color text NOT NULL DEFAULT 'neutral' CHECK (color IN ('terracotta', 'sage', 'slate', 'ochre', 'neutral')),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_time_order CHECK (start_time < end_time)
);

CREATE INDEX calendar_events_owner_day_start_idx
  ON calendar_events(owner_id, event_date, start_time, id);
