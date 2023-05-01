import click

from data_products.dap import DAP


@click.group(help='Automate the setup of data products')
def cli():
    pass


@cli.command(help='Setup data products and create a YAML configuration file.')
def setup():
    dap = DAP()
    dap.setup()


@cli.command(help='Create data products')
@click.option('--force', is_flag=True, help='Force the creation of everything by overriding existing if needed')
@click.option('-m', '--model', help='Stop after creating the given model name (e.g. stripe_price). '
                                    'Implies force. Useful for testing')
@click.option('--no-cache', is_flag=True, help='Create models without cache')
def create(force, model, no_cache):
    if model:
        force = True

    dap = DAP()
    dap.create(force=force, model=model, no_cache=no_cache)
