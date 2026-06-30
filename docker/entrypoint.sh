#!/bin/sh
set -e

echo "Collecting static files"
python manage.py collectstatic --noinput --skip-checks --clear

echo "Applying database migrations"
python manage.py migrate --noinput

echo "Ensuring required seed data exists (idempotent, safe to run every start)"
python manage.py loaddata languages 2>/dev/null || \
python manage.py loaddata language 2>/dev/null || \
echo " (no languages fixture found via loaddata - skipping)"

python manage.py shell -c "
from django.contrib.sites.models import Site
from wger.gym.models import Gym
from wger.config.models import GymConfig
Site.objects.get_or_create(pk=1, defaults={'domain': 'localhost', 'name': 'wger'})
Gym.objects.get_or_create(pk=1, defaults={'name': 'Default Gym'})
GymConfig.objects.get_or_create(pk=1)
print(' Seed data OK: Site, Gym, GymConfig present.')
"

echo "Starting Gunicorn"
exec gunicorn wger.wsgi:application \
    --bind 0.0.0.0:8000 \
    --workers 3 \
    --timeout 120
