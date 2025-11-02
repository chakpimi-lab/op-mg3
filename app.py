from flask import Flask, render_template, request, redirect, url_for, send_file, flash
from flask_sqlalchemy import SQLAlchemy
import os, io, datetime, config

app = Flask(__name__)
app.secret_key = config.SECRET_KEY
db_path = os.path.join(os.path.dirname(__file__), 'panel.db')
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///' + db_path
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    max_bandwidth = db.Column(db.Integer, default=0)  # kbit
    max_traffic = db.Column(db.Integer, default=0)    # bytes quota
    ovpn = db.Column(db.Text, nullable=True)
    ip_assigned = db.Column(db.String(64), nullable=True)
    created = db.Column(db.DateTime, default=datetime.datetime.utcnow)

db.create_all()

def auth_ok(req):
    return req.form.get('username')==config.ADMIN_USER and req.form.get('password')==config.ADMIN_PASS

def require_auth(f):
    from functools import wraps
    @wraps(f)
    def wrapped(*args, **kwargs):
        if request.cookies.get('panel_auth')!='1':
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return wrapped

@app.route('/login', methods=['GET','POST'])
def login():
    if request.method=='POST':
        if auth_ok(request):
            resp = redirect(url_for('dashboard'))
            resp.set_cookie('panel_auth','1',httponly=True)
            return resp
        flash('Invalid credentials','danger')
    return render_template('login.html')

@app.route('/logout')
def logout():
    resp = redirect(url_for('login'))
    resp.delete_cookie('panel_auth')
    return resp

def next_available_ip():
    # find next free last octet between start and end
    used = set()
    for u in User.query.all():
        if u.ip_assigned:
            try:
                used.add(int(u.ip_assigned.split('.')[-1]))
            except:
                pass
    for o in range(config.CCD_START_OCTET, config.CCD_END_OCTET+1):
        if o not in used:
            return config.CCD_NETWORK_PREFIX + str(o)
    return None

def write_ccd_and_configs(username, ip, bw_kbit, quota_bytes):
    # create ccd file
    ccd_path = '/etc/openvpn/ccd'
    try:
        os.makedirs(ccd_path, exist_ok=True)
        with open(os.path.join(ccd_path, username), 'w') as f:
            f.write(f'ifconfig-push {ip} 255.255.255.0\n')
    except Exception as e:
        app.logger.error('failed write ccd: %s', e)
    # update bandwidth.conf and quota.conf: replace or append entry
    bw_file = '/etc/openvpn/bandwidth.conf'
    quota_file = '/etc/openvpn/quota.conf'
    def replace_or_append(path, key, val):
        lines = []
        if os.path.exists(path):
            with open(path,'r') as f:
                lines = f.readlines()
        found = False
        with open(path,'w') as f:
            for L in lines:
                if L.strip().startswith(key+' '):
                    f.write(f"{key} {val}\n")
                    found = True
                else:
                    f.write(L)
            if not found:
                f.write(f"{key} {val}\n")
    try:
        replace_or_append(bw_file, username, str(bw_kbit))
        replace_or_append(quota_file, username, str(quota_bytes))
    except Exception as e:
        app.logger.error('failed update confs: %s', e)

@app.route('/')
@require_auth
def dashboard():
    users = User.query.order_by(User.id).all()
    return render_template('dashboard.html', users=users)

@app.route('/add', methods=['GET','POST'])
@require_auth
def add_user():
    if request.method=='POST':
        username = request.form['username'].strip()
        if not username:
            flash('Username required','danger'); return redirect(url_for('add_user'))
        bw = int(request.form.get('bandwidth') or 0)
        quota = int(request.form.get('quota') or 0)
        # assign IP
        ip = next_available_ip()
        if ip is None:
            flash('No available IPs in pool','danger'); return redirect(url_for('add_user'))
        # generate simple .ovpn content
        ovpn_content = f"""client
dev tun
proto udp
remote {config.OVPN_SERVER_ADDRESS} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-CBC
verb 3
# user: {username}
# ifconfig-push {ip} 255.255.255.0 (will be set server-side via CCD)
"""
        u = User(username=username, max_bandwidth=bw, max_traffic=quota, ovpn=ovpn_content, ip_assigned=ip)
        db.session.add(u)
        db.session.commit()
        # write CCD and confs
        try:
            write_ccd_and_configs(username, ip, bw, quota)
        except Exception as e:
            app.logger.error('write ccd error %s', e)
        flash('User added and CCD created','success')
        return redirect(url_for('dashboard'))
    return render_template('add.html')

@app.route('/edit/<int:user_id>', methods=['GET','POST'])
@require_auth
def edit(user_id):
    u = User.query.get_or_404(user_id)
    if request.method=='POST':
        u.max_bandwidth = int(request.form.get('bandwidth') or 0)
        u.max_traffic = int(request.form.get('quota') or 0)
        db.session.commit()
        # update config files
        write_ccd_and_configs(u.username, u.ip_assigned, u.max_bandwidth, u.max_traffic)
        flash('Saved','success')
        return redirect(url_for('dashboard'))
    return render_template('edit.html', user=u)

@app.route('/delete/<int:user_id>', methods=['POST'])
@require_auth
def delete(user_id):
    u = User.query.get_or_404(user_id)
    # remove ccd file and conf entries
    try:
        ccd_file = '/etc/openvpn/ccd/' + u.username
        if os.path.exists(ccd_file):
            os.remove(ccd_file)
    except Exception as e:
        app.logger.error('failed remove ccd: %s', e)
    # remove from confs
    def remove_key(path, key):
        if not os.path.exists(path): return
        with open(path,'r') as f:
            lines = f.readlines()
        with open(path,'w') as f:
            for L in lines:
                if not L.strip().startswith(key+' '):
                    f.write(L)
    remove_key('/etc/openvpn/bandwidth.conf', u.username)
    remove_key('/etc/openvpn/quota.conf', u.username)
    db.session.delete(u)
    db.session.commit()
    flash('Deleted','success')
    return redirect(url_for('dashboard'))

@app.route('/download/<int:user_id>')
@require_auth
def download(user_id):
    u = User.query.get_or_404(user_id)
    mem = io.BytesIO(u.ovpn.encode('utf-8'))
    return send_file(mem, attachment_filename=f"{u.username}.ovpn", as_attachment=True)

if __name__=='__main__':
    app.run(host='0.0.0.0', port=8080)
