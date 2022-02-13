let app = new Vue({
  el: '#app',
  data: function()  { return {
    recentTemps: [492,492,5,32,1],
    violatingTemps: [492, 492],
    dataTimer: '',
    profileTimer: '',
    sensorProfile: {},
    updatedLocation: '',
    updatedName: '',
    updatedThreshold: '',
    updatedPhoneNumber: '',
  }},
  created() {
    this.fetchData();
    this.dataTimer = setInterval(this.fetchData, 10000);
    this.getProfile();
    this.profileTimer = setInterval(this.getProfile, 10000);
  },
  methods: {
    fetchData() {
      let recentTempsUrl = 'http://localhost:3000/c/ckyugkt53005pgwvode6t1egr/query/temperature_store/temperatures';
      axios.get(recentTempsUrl)
        .then(response => {
          console.log(response.data);
          let sortedData = response.data.sort( (firstElem, secondElem) => firstElem.time < secondElem.time) 
          let mappedTemps = sortedData.map(objectToDecompose => objectToDecompose.temperature);
          console.log("Recent: " + mappedTemps);
          this.recentTemps = mappedTemps
        })
        .catch(error => {
          console.log(error)
        });

      let thresholdUrl = 'http://localhost:3000/c/ckyugkt53005pgwvode6t1egr/query/temperature_store/threshold_violations';
      axios.get(thresholdUrl)
        .then(response => {
          let sortedData = response.data.sort( (firstElem, secondElem) => firstElem.time < secondElem.time) 
          let mappedTemps = sortedData.map(objectToDecompose => objectToDecompose.temperature);
          console.log("Violating: " + mappedTemps);
          this.violatingTemps = mappedTemps
        })
        .catch(error => {
          console.log(error)
        });
    },
    updateProfile() {
      console.log("in update profile");
      let updateProfileUrl = new URL("http://localhost:3000/c/ckyugkt53005pgwvode6t1egr/event-wait/sensor/profile_updated?");
      if (this.updatedLocation) {
        updateProfileUrl.searchParams.set("location", this.updatedLocation);
        this.sensorProfile.location = this.updatedLocation;
        this.updatedLocation = '';
      }
      if (this.updatedName) {
        updateProfileUrl.searchParams.set("name", this.updatedName);
        this.sensorProfile.name = this.updatedName;
        this.updatedName = '';
      }
      if (this.updatedThreshold) {
        updateProfileUrl.searchParams.set("threshold", this.updatedThreshold);
        this.sensorProfile.threshold = this.updatedThreshold;
        this.updatedThreshold = '';
      }
      if (this.updatedPhoneNumber) {
        updateProfileUrl.searchParams.set("phone_number", this.updatedPhoneNumber);
        this.sensorProfile.phone_number = this.updatedPhoneNumber;
        this.updatedPhoneNumber = '';
      }

      console.log(updateProfileUrl.toString())

      axios.get(updateProfileUrl.toString())
        .then(_ => {
          this.fetchData();
        })
        .catch(_ => {
          console.log("Failed to update profile")
        });
    },
    getProfile() {
      let getProfileUrl = 'http://localhost:3000/c/ckyugkt53005pgwvode6t1egr/query/sensor_profile/getProfile';

      axios.get(getProfileUrl)
        .then(response => {
          console.log("Profile");
          console.log(response.data);
          this.sensorProfile = response.data;
        })
        .catch(error => {
          console.log(error)
        });
    },
  },
  computed: {
    currentTemp() {
      return this.recentTemps[0] ?? "No temps recorded"
    }
  },
});