from ..base import *


DEBUG = True
ALLOWED_HOSTS = ['*']

secrets = load_secret(os.path.join(os.path.dirname(__file__), 'secrets.json'))

SECRET_KEY = get_secret(secrets, 'SECRET_KEY')

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': get_secret(secrets, 'DB_NAME'),
        'USER': get_secret(secrets, 'DB_USER'),
        'PASSWORD': get_secret(secrets, 'DB_PASSWORD'),
        'HOST': get_secret(secrets, 'DB_HOST'),
        'PORT': '5432',
    }
}