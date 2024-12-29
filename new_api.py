from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
import bcrypt
import pyodbc

# Database connection
connection = pyodbc.connect(
    "Driver={ODBC Driver 17 for SQL Server};"
    "Server=LAPTOP-OUSQSNAL\SALAZARSQL;"
    "Database=CarpoolingSystem2;"
    "Trusted_Connection=yes;"
)
cursor = connection.cursor()

app = Flask(__name__)
app.secret_key = 'secure_secret_key'  # For session management

CORS(app)

# Serve the login page at the root route
@app.route('/')
def home():
    return render_template('login.html')


# API endpoint for login
@app.route('/login', methods=['POST'])
def login():
    data = request.json
    email = data.get('email')
    password = data.get('password')
    role = data.get('role').title()
    print(email, password, role)

    # Validate input
    if not all([email, password, role]):
        return jsonify({"success": False, "message": "All fields are required."}), 400

    # Query user details and role
    cursor.execute("""
        SELECT u.UserID, u.PasswordHash, r.RoleName 
        FROM Users u 
        JOIN Roles r ON u.RoleID = r.RoleID 
        WHERE u.Email = ?
    """, (email,))
    user = cursor.fetchone()

    if not user:
        return jsonify({"success": False, "message": "Invalid credentials."}), 401

    user_id, hashed_password, role = user

    # Verify password
    if not bcrypt.checkpw(password.encode('utf-8'), hashed_password.encode('utf-8')):
        cursor.execute("EXEC sp_LogLoginActivity ?, ?, ?, ?", (None, 'LoginAttempt', request.remote_addr, 0))
        connection.commit()
        return jsonify({"success": False, "message": "Invalid credentials."}), 401

    # Log successful login
    cursor.execute("EXEC sp_LogLoginActivity ?, ?, ?, ?", (user_id, 'Login', request.remote_addr, 1))
    connection.commit()

    # Define dashboard URLs

    return jsonify({"message": "Login Successful", "success": True, "role": role, "redirect_url": '/dashboard', "user_id": user_id}), 200


# Route for the signup page
@app.route('/signup', methods=['POST', 'GET'])
def signup():
    if request.method == 'GET':
        return render_template('signup.html')
    else:
        pass
    data = request.get_json()
    name = data.get('name')
    email = data.get('email')
    phonenumber = data.get('phonenumber')
    password = data.get('password')
    role = data.get('role', 'Rider').title()  # Default role is Rider

    # Validate input
    if not all([name, email, phonenumber, password, role]):
        return jsonify({"success": False, "message": "All fields are required."}), 400

    # Hash the password
    hashed_password = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    # Fetch role ID
    cursor.execute("SELECT RoleID FROM Roles WHERE RoleName = ?", (role,))
    role_id = cursor.fetchone()
    if not role_id:
        return jsonify({"success": False, "message": "Invalid role."}), 400

    try:
        # Insert user into the database
        cursor.execute("""
            INSERT INTO Users (FullName, Email, PhoneNumber, PasswordHash, RoleID)
            VALUES (?, ?, ?, ?, ?)
        """, (name, email, phonenumber, hashed_password, role_id[0]))
        connection.commit()

        return jsonify({"success": True, "message": "Signup successful."}), 201
    except Exception as e:
        print("Error:", e)
        return jsonify({"success": False, "message": "An error occurred during signup."}), 500

# Logout route
@app.route('/logout', methods=['GET'])
def logout():
    return jsonify({"success": True, "message": "Logged out successfully."})

# @app.route('/dashboard')
# def dashboard():
#     user_id = request.args.get('user_id')
#     print(user_id)

#      # Query user details and role
#     cursor.execute("""SELECT u.UserID, u.FullName, u.Email, u.PhoneNumber, r.RoleName FROM Users u INNER JOIN Roles r on u.RoleID = r.RoleID WHERE u.UserID = ?""", (user_id,))
#     user = cursor.fetchone()

#     UserID, FullName, Email, PhoneNumber, Role = user

#     # Example data you might want to pass to the template
#     customer_name = FullName  # You can fetch this from your database using the user_id
#     profile_info = f"Email: {Email}\nPhoneNumber: {PhoneNumber}\nRole: {Role}"  # Example profile info
#     my_rides = ["Ride 1", "Ride 2", "Ride 3"]  # Example rides (fetch these from the database)
#     available_rides = ["Ride A", "Ride B", "Ride C"]  # Example available rides

#     return render_template(
#         'dashboard.html',
#         customer_name=customer_name,
#         profile_info=profile_info,
#         my_rides=my_rides,
#         available_rides=available_rides
#     )

@app.route('/dashboard')
def dashboard():
    user_id = request.args.get('user_id')

    # Query user details and role
    cursor.execute("""
        SELECT u.UserID, u.FullName, u.Email, u.PhoneNumber, r.RoleName 
        FROM Users u 
        INNER JOIN Roles r on u.RoleID = r.RoleID 
        WHERE u.UserID = ?
    """, (user_id,))
    user = cursor.fetchone()

    if not user:
        return "User not found", 404

    UserID, FullName, Email, PhoneNumber, Role = user

    # Query user's rides as driver
    cursor.execute("""
        SELECT RideID, StartLocation, Destination, RideDate, RideTime, AvailableSeats, CostPerSeat, RideStatus 
        FROM Rides 
        WHERE DriverID = ?
    """, (user_id,))
    my_rides = cursor.fetchall()

    # Query available rides (excluding user's rides)
    cursor.execute("""
        SELECT RideID, StartLocation, Destination, RideDate, RideTime, AvailableSeats, CostPerSeat 
        FROM Rides 
        WHERE DriverID != ? AND RideStatus = 'Scheduled'
    """, (user_id,))
    available_rides = cursor.fetchall()

    # Prepare data for rendering
    user_info = {
        "FullName": FullName,
        "Email": Email,
        "PhoneNumber": PhoneNumber,
        "Role": Role
    }

    return render_template(
        'dashboard.html',
        user_info=user_info,
        my_rides=my_rides,
        available_rides=available_rides
    )

@app.route('/add_ride', methods=['POST'])
def add_ride():
    try:
        data = request.get_json()
        driver_id = data.get('DriverID')
        start_location = data.get('startLocation')
        destination = data.get('destination')
        ride_date = data.get('rideDate')
        ride_time = data.get('rideTime')
        available_seats = data.get('availableSeats')
        cost_per_seat = data.get('costPerSeat')
        # driver_id = request.args.get('user_id')  # Fetch driver ID

        if not all([start_location, destination, ride_date, ride_time, available_seats, cost_per_seat]):
            return jsonify({"success": False, "message": "All fields are required."}), 400

        # Insert the ride into the database
        cursor.execute("""
            INSERT INTO Rides (DriverID, StartLocation, Destination, RideDate, RideTime, AvailableSeats, CostPerSeat)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (driver_id, start_location, destination, ride_date, ride_time, available_seats, cost_per_seat))
        connection.commit()

        return jsonify({"success": True, "message": "Ride added successfully!"}), 201
    except Exception as e:
        app.logger.error(f"Error in /add_ride: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500



if __name__ == '__main__':
    app.run(port=5500)
