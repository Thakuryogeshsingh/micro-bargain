FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# GDAL/GEOS/PROJ are required by GeoDjango (PostGIS queries)
RUN apt-get update && apt-get install -y --no-install-recommends \
        gdal-bin libgdal-dev libgeos-dev libproj-dev binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG REQUIREMENTS=production
COPY requirements/ requirements/
RUN pip install --no-cache-dir -r requirements/${REQUIREMENTS}.txt

COPY . .

# Collect (and compress) static files at build time so the container starts fast: Render fails a deploy
# when the web port is not open within a few minutes. Placeholder values only let the settings load;
# collectstatic does not touch the database.
RUN DJANGO_SETTINGS_MODULE=config.settings.production DJANGO_SECRET_KEY=build-only ALLOW_TEST_BACKENDS=True     POSTGRES_DB=build POSTGRES_USER=build POSTGRES_PASSWORD=build     python manage.py collectstatic --noinput > /dev/null

EXPOSE 8000
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
