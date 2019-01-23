import json
import uuid
import os
import argparse

DEFAULT_SETTINGS = {'projects': [], 'settings': {'send_metrics':True,'shell':'sh'},'lastNewsDate':0}

def check_and_create_settings(path):
    json_data = DEFAULT_SETTINGS

    if os.path.exists(path):
        with open(path, 'r') as settings_file:
            try:
                json_data = json.load(settings_file)

                projects = json_data.get('projects', [])
                settings = json_data.get('settings', {'send_metrics':True,'shell':'sh'})
                lastdate = json_data.get('lastNewsDate', 0)

                json_data['projects'] = projects
                json_data['settings'] = settings
                json_data['lastNewsDate'] = lastdate
            except:
                print('could not parse json from settings, creating new')

    with open(path, 'w') as settings_file:
        json.dump(json_data, settings_file)

def parse_arguments_to_template(args):
    template = {
        'title': args.title,
        'path': args.compose_file,
        'name': args.name,
        'services': {},
        'id': uuid.uuid4().__str__(),
        'selected': args.selected
    }

    return template

if __name__ == '__main__':
    user_name = os.environ.get('USER', None)

    if not user_name:
        print('Could not get user from environment variable')
        exit(-1)

    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--compose_file', type=str, required=True)
    parser.add_argument('-t', '--title', type=str, default='no_title')
    parser.add_argument('-n', '--name', type=str, default='no_name')
    parser.add_argument('-s', '--selected', type=bool, default=False)
    parser.add_argument('-e', '--settings_file', type=str, default='/home/{}/Settings'.format(user_name))

    args = parser.parse_args()

    check_and_create_settings(args.settings_file)

    with open(args.settings_file, 'r') as settings_file:
        settings_json = json.load(settings_file)

    new_settings_slot = parse_arguments_to_template(args)

    if 'projects' not in settings_json:
        settings_json['projects'] = []

    settings_json['projects'].append(new_settings_slot)

    print('new slot added to settings: {}'.format(new_settings_slot))
    print('total of compose slots in settings {}'.format(len(settings_json['projects'])))

    with open(args.settings_file, 'w') as settings_file:
        json.dump(settings_json, settings_file)

    print('successfully added and saved settings')
